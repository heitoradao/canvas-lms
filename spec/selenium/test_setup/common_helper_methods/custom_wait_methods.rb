# frozen_string_literal: true

#
# Copyright (C) 2015 - present Instructure, Inc.
#
# This file is part of Canvas.
#
# Canvas is free software: you can redistribute it and/or modify it under
# the terms of the GNU Affero General Public License as published by the Free
# Software Foundation, version 3 of the License.
#
# Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
# WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
# A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
# details.
#
# You should have received a copy of the GNU Affero General Public License along
# with this program. If not, see <http://www.gnu.org/licenses/>.

module CustomWaitMethods
  def wait_for_dom_ready
    result = driver.execute_async_script(<<-JS)
      var callback = arguments[arguments.length - 1];
      if (document.readyState === "complete") {
        callback(0);
      } else {
        var leftPageBeforeDomReady = callback.bind(null, -1);
        window.addEventListener("beforeunload", leftPageBeforeDomReady);
        document.onreadystatechange = function() {
          if (document.readyState === "complete") {
            window.removeEventListener("beforeunload", leftPageBeforeDomReady);
            callback(0);
          }
        }
      };
    JS
    raise "left page before domready" if result != 0
  end

  # If we're looking for the loading image, we can't just do a normal assertion, because the image
  # could end up getting loaded too quickly.
  def wait_for_transient_element(selector)
    driver.execute_script(<<-JS)
      window.__WAIT_FOR_LOADING_IMAGE = 0
      window.__WAIT_FOR_LOADING_IMAGE_CALLBACK = null

      var _checkAddedNodes = function(addedNodes) {
        for(var newNode of addedNodes) {
          if(newNode.matches('#{selector}') || newNode.querySelector('#{selector}')) {
            window.__WAIT_FOR_LOADING_IMAGE = 1
          }
        }
      }

      var _checkRemovedNodes = function(removedNodes) {
        if(window.__WAIT_FOR_LOADING_IMAGE !== 1) {
          return
        }

        for(var newNode of removedNodes) {
          if(newNode.matches('#{selector}') || newNode.querySelector('#{selector}')) {
            observer.disconnect()

            window.__WAIT_FOR_LOADING_IMAGE = 2
            window.__WAIT_FOR_LOADING_IMAGE_CALLBACK && window.__WAIT_FOR_LOADING_IMAGE_CALLBACK()
          }
        }
      }

      var callback = function(mutationsList, observer) {
        for(var record of mutationsList) {
          _checkAddedNodes(record.addedNodes)
          _checkRemovedNodes(record.removedNodes)
        }
      }
      var observer = new MutationObserver(callback)
      observer.observe(document.body, { subtree: true, childList: true })
    JS

    yield

    result = driver.execute_async_script(<<-JS)
      var callback = arguments[arguments.length - 1]
      if (window.__WAIT_FOR_LOADING_IMAGE == 2) {
        callback(0)
      }
      window.__WAIT_FOR_LOADING_IMAGE_CALLBACK = function() {
        callback(0)
      }
    JS
    raise "element #{selector} did not appear or was not transient" if result != 0
  end

  def wait_for_ajax_requests(bridge = nil)
    bridge = driver if bridge.nil?

    result = bridge.execute_async_script(<<-JS)
      var callback = arguments[arguments.length - 1];
      // see code in ui/boot/index.js for where
      // __CANVAS_IN_FLIGHT_XHR_REQUESTS__ and 'canvasXHRComplete' come from
      if (typeof window.__CANVAS_IN_FLIGHT_XHR_REQUESTS__  === 'undefined') {
        callback(-1);
      } else if (window.__CANVAS_IN_FLIGHT_XHR_REQUESTS__ === 0) {
        callback(0);
      } else {
        var fallbackCallback = window.setTimeout(function() {
          callback(-2);
        }, #{(SeleniumDriverSetup.timeouts[:script] * 1000) - 500})

        function onXHRCompleted () {
          // while there are no outstanding requests, a new one could be
          // chained immediately afterwards in this thread of execution,
          // e.g. $.get(url).then(() => $.get(otherUrl))
          //
          // so wait a tick just to be sure we're done
          setTimeout(function() {
            if (window.__CANVAS_IN_FLIGHT_XHR_REQUESTS__ === 0) {
              window.removeEventListener('canvasXHRComplete', onXHRCompleted)
              window.clearTimeout(fallbackCallback);
              callback(0)
            }
          }, 0)
        }
        window.addEventListener('canvasXHRComplete', onXHRCompleted)
      }
    JS
    raise "ajax requests not completed" if result == -2

    result
  end

  def wait_for_animations(bridge = nil)
    bridge = driver if bridge.nil?

    bridge.execute_async_script(<<-JS)
      var callback = arguments[arguments.length - 1];
      if (typeof($) == 'undefined') {
        callback(-1);
      } else if ($.timers.length == 0) {
        callback(0);
      } else {
        var _stop = $.fx.stop;
        $.fx.stop = function() {
          $.fx.stop = _stop;
          _stop.apply(this, arguments);
          callback(0);
        }
      }
    JS
  end

  def wait_for_ajaximations(bridge = nil)
    bridge = driver if bridge.nil?

    wait_for_ajax_requests(bridge)
    wait_for_animations(bridge)
  end

  def wait_for_initializers(bridge = nil)
    bridge = driver if bridge.nil?

    bridge.execute_async_script <<~JS
      var callback = arguments[arguments.length - 1];

      // If canvasReadyState isn't defined, we're likely in an IFrame (such as the RCE)
      if (!window.canvasReadyState || window.canvasReadyState === 'complete') {
        callback()
      }
      else {
        window.addEventListener('canvasReadyStateChange', function() {
          if (window.canvasReadyState === 'complete') {
            callback()
          }
        })
      }
    JS
  end

  def wait_for_children(selector)
    has_children = false
    while has_children == false
      has_children = element_has_children?(selector)
      wait_for_dom_ready
    end
  end

  def wait_for_stale_element(selector, jquery_selector: false)
    stale_element = true
    while stale_element == true
      begin
        wait_for_dom_ready
        if jquery_selector
          fj(selector)
        else
          f(selector)
        end
      rescue Selenium::WebDriver::Error::NoSuchElementError
        stale_element = false
      end
    end
  end

  def pause_ajax
    SeleniumDriverSetup.request_mutex.synchronize { yield }
  end

  def keep_trying_until(seconds = SeleniumDriverSetup::SECONDS_UNTIL_GIVING_UP)
    frd_error = Selenium::WebDriver::Error::TimeoutError.new
    wait_for(timeout: seconds, method: :keep_trying_until) do
      yield
    rescue SeleniumExtensions::Error, Selenium::WebDriver::Error::StaleElementReferenceError # don't keep trying, abort ASAP
      raise
    rescue StandardError, RSpec::Expectations::ExpectationNotMetError
      frd_error = $ERROR_INFO
      nil
    end or CallStackUtils.raise(frd_error)
  end

  # pass in an Element pointing to the textarea that is tinified.
  def wait_for_tiny(element)
    # TODO: Better to wait for an event from tiny?
    parent = element.find_element(:xpath, '..')
    tiny_frame = nil
    keep_trying_until do
      tiny_frame = disable_implicit_wait { parent.find_element(:css, 'iframe') }
    rescue => e
      puts e.inspect
      false
    end
    tiny_frame
  end

  # a slightly modified version of wait_for_tiny
  # that's simpler for the normal case where
  # there's only 1 RCE on  the pge
  def wait_for_rce(element = nil)
    element = f(element) if element.is_a? String
    element ||= f('.rce-wrapper')
    tiny_frame = nil
    keep_trying_until do
      tiny_frame = disable_implicit_wait { element.find_element(:css, 'iframe') }
    rescue => e
      puts e.inspect
      false
    end
    tiny_frame
  end

  def disable_implicit_wait
    ::SeleniumExtensions::FinderWaiting.disable do
      yield
    end
  end

  # little wrapper around Selenium::WebDriver::Wait, notably it:
  # * is less verbose
  # * returns false (rather than raising) if the block never returns true
  # * doesn't rescue :allthethings: like keep_trying_until
  # * prevents nested waiting, cuz that's terrible
  def wait_for(*args, &block)
    ::SeleniumExtensions::FinderWaiting.wait_for(*args, &block)
  end

  def wait_for_no_such_element(method: nil, timeout: SeleniumExtensions::FinderWaiting.timeout)
    wait_for(method: method, timeout: timeout, ignore: []) do
      # so find_element calls return ASAP
      disable_implicit_wait do
        yield
        false
      end
    end
  rescue Selenium::WebDriver::Error::NoSuchElementError
    true
  end
end
