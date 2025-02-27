# frozen_string_literal: true

#
# Copyright (C) 2021 - present Instructure, Inc.
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

require 'spec_helper'

describe MicrosoftSync::GraphService::SpecialCase do
  let(:my_class) { Class.new }

  let(:cases) do
    [
      described_class.new(400, /foo/, result: '400_foo'),
      described_class.new(400, /bar/, result: '400_bar'),
      described_class.new(401, /bar/, result: '401_bar'),
      described_class.new(401, /myclass/, result: my_class),
    ]
  end

  it 'matches based on status code and body regex' do
    expect(described_class.match(cases, status_code: 404, body: '_bar_')).to be_nil
    expect(described_class.match(cases, status_code: 400, body: '_bar_')).to eq('400_bar')
    expect(described_class.match(cases, status_code: 401, body: '_bar_')).to eq('401_bar')
    expect(described_class.match(cases, status_code: 401, body: 'foo')).to be_nil
  end

  it 'instantiates the value if it is a class' do
    expect(described_class.match(cases, status_code: 401, body: '=myclass!')).to \
      be_instance_of(my_class)
  end
end
