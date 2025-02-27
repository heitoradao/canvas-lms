# frozen_string_literal: true

#
# Copyright (C) 2013 - present Instructure, Inc.
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
#

require 'hash_view'
require 'controller_view'

class ControllerListView < HashView
  def initialize(name, controllers)
    super()
    @controllers = controllers.map do |ctrl|
      ControllerView.new(ctrl)
    end
    @name = name
  end

  def symbolic_name
    @name.underscore.gsub(/\s+/, '_')
  end

  def config_domain_yaml
    YAML.load(File.read(File.join(Rails.root, 'config', 'domain.yml'))) if File.exist?(File.join(Rails.root, 'config', 'domain.yml'))
  end

  def canvas_url
    if (config = config_domain_yaml[Rails.env])
      if config['ssl']
        "https://"
      else
        "http://"
      end + config['domain']
    end
  end

  def domain
    ENV["CANVAS_DOMAIN"] || (config_domain_yaml ? canvas_url : "https://canvas.instructure.com")
  end

  def swagger_file
    "#{symbolic_name}.json"
  end

  def swagger_reference
    {
      "path" => '/' + swagger_file,
      "description" => @name,
    }
  end

  def swagger_api_listing
    {
      "apiVersion" => "1.0",
      "swaggerVersion" => "1.2",
      "basePath" => "#{domain}/api",
      "resourcePath" => "/#{symbolic_name}",
      "produces" => ["application/json"],
      "apis" => apis,
      "models" => models
    }
  end

  def apis
    [].tap do |list|
      @controllers.each do |controller|
        controller.methods.each do |method|
          method.routes.each do |route|
            list << route.to_swagger
          end
        end
      end
    end
  end

  def models
    {}.tap do |m|
      merge = lambda do |name, hash|
        m.merge! hash
      rescue JSON::ParserError
        puts "Unable to parse model: #{name} (#{ctrl.raw_name})"
      end

      # If @object tags are available to describe a class of object, we'll
      # use it if we must. From the examples given by the JSON that follows
      # the @object tag, we generate a best-guess JSON-schema (draft 4).
      #
      # If a @model tag is present, this is the preferred way to describe
      # API classes, and it will be merged last.
      #
      # See https://github.com/wordnik/swagger-core/wiki/Datatypes for a
      # description of the models schema we are trying to generate here.
      @controllers.each do |ctrl|
        ctrl.objects.each { |object| merge[object.name, object.to_model.json_schema] }
        ctrl.models.each { |model| merge[model.name, model.json_schema] }
      end
    end
  end
end
