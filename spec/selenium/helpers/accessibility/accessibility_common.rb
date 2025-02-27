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

def val_page_title_present
  expect(driver.title).not_to be_nil
end

def val_page_title_not_empty
  expect(driver.title).not_to eq ''
end

def val_image_alt_tags_present
  images = find_all_elements('img')
  if images.length > 0
    val_all_elements_attribute_presence(images, 'alt')
  end
end

def val_image_alt_tags_not_empty
  images = find_all_elements('img')
  if images.length > 0
    val_all_elements_attribute_not_empty(images, 'alt')
  end
end

def val_image_alt_tags_max_length
  images = find_all_elements('img')
  if images.length > 0
    val_text_max_length(images, 56)
  end
end

def val_link_name_uniqueness
  links_text = []
  links = find_all_elements('a')
  if links.length > 0
    links.each do |link|
      links_text << link.attribute('href') if link.attribute('href') != ''
    end
    expect(links_text.uniq.length).to eq links_text.length
  end
end

def val_input_alt_tags_present
  inputs = find_all_elements('input')
  if inputs.length > 0
    val_all_elements_attribute_presence(inputs, 'alt')
  end
end

def val_input_alt_tags_not_empty
  inputs = find_all_elements('input')
  if inputs.length > 0
    val_all_elements_attribute_not_empty(inputs, 'alt')
  end
end

def val_html_lang_attribute_present
  inputs = find_all_elements('html')
  val_all_elements_attribute_presence(inputs, 'lang')
end

def val_html_lang_attribute_not_empty
  images = find_all_elements('html')
  val_all_elements_attribute_not_empty(images, 'lang')
end

def val_h1_populated
  headers = find_all_elements('h1')
  expect(headers).not_to be_empty
  val_all_elements_attribute_not_empty(headers, 'text')
end

def find_all_elements(type)
  driver.find_elements(:tag_name, type.to_s)
end

def val_all_tables_have_heading
  tables = find_all_elements('table')
  if tables.length > 0
    tables.each { |t| expect(t.find_elements(:tag_name, 'th').count).to be > 0 }
  end
end

def val_all_elements_attribute_presence(elements, attrib)
  elements.each { |element| expect(element.attribute(attrib.to_s)).not_to be_nil }
end

def val_all_elements_attribute_not_empty(elements, attrib)
  elements.each { |element| expect(element.attribute(attrib.to_s)).not_to eq '' }
end

def val_text_max_length(elements, max_length)
  elements.each { |element| expect(element.text.length).to be < max_length.to_i }
end
