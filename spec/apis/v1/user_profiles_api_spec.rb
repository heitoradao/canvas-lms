# frozen_string_literal: true

#
# Copyright (C) 2012 Instructure, Inc.
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

require_relative '../api_spec_helper'
require_relative '../../helpers/k5_common'

# FIXME: don't copy paste
class TestUserApi
  include Api::V1::UserProfile
  attr_accessor :services_enabled, :context, :current_user

  def service_enabled?(service)
    @services_enabled.include? service
  end

  def avatar_image_url(user_id)
    "avatar_image_url(#{user_id})"
  end

  def initialize
    @domain_root_account = Account.default
  end
end

def default_avatar_url
  "http://www.example.com/images/messages/avatar-50.png"
end

describe "User Profile API", type: :request do
  include K5Common

  before :once do
    @admin = account_admin_user
    @admin_lti_user_id = Lti::Asset.opaque_identifier_for(@admin)
    course_with_student(:user => user_with_pseudonym(:name => 'Student', :username => 'pvuser@example.com'))
    @student.pseudonym.update_attribute(:sis_user_id, 'sis-user-id')
    Lti::Asset.opaque_identifier_for(@student)
    @user = @admin
    Account.default.tap { |a| a.enable_service(:avatars) }.save
    user_with_pseudonym(:user => @user)
  end

  it "returns another user's avatars, if allowed" do
    json = api_call(:get, "/api/v1/users/#{@student.id}/avatars",
                    :controller => "profile", :action => "profile_pics", :user_id => @student.to_param, :format => 'json')
    expect(json.map { |j| j['type'] }.sort).to eql ['gravatar', 'no_pic']
  end

  it "returns user info for users with no pseudonym" do
    @me = @user
    new_user = user_factory(:name => 'new guy')
    @user = @me
    @course.enroll_user(new_user, 'ObserverEnrollment')
    Account.site_admin.account_users.create!(user: @user)
    json = api_call(:get, "/api/v1/users/#{new_user.id}/profile",
                    :controller => "profile", :action => "settings", :user_id => new_user.to_param, :format => 'json')
    expect(json).to eq({
                         'id' => new_user.id,
                         'name' => 'new guy',
                         'sortable_name' => 'guy, new',
                         'short_name' => 'new guy',
                         'sis_user_id' => nil,
                         'login_id' => nil,
                         'integration_id' => nil,
                         'primary_email' => nil,
                         'title' => nil,
                         'bio' => nil,
                         'avatar_url' => default_avatar_url,
                         'time_zone' => 'Etc/UTC',
                         'locale' => nil
                       })

    get("/courses/#{@course.id}/students")
  end

  it "returns this user's profile" do
    json = api_call(:get, "/api/v1/users/self/profile",
                    :controller => "profile", :action => "settings", :user_id => 'self', :format => 'json')
    expect(json).to eq({
                         'id' => @admin.id,
                         'name' => 'User',
                         'sortable_name' => 'User',
                         'short_name' => 'User',
                         'sis_user_id' => nil,
                         'integration_id' => nil,
                         'primary_email' => 'nobody@example.com',
                         'login_id' => 'nobody@example.com',
                         'avatar_url' => default_avatar_url,
                         'calendar' => { 'ics' => "http://www.example.com/feeds/calendars/user_#{@admin.uuid}.ics" },
                         'lti_user_id' => @admin_lti_user_id,
                         'title' => nil,
                         'bio' => nil,
                         'time_zone' => 'Etc/UTC',
                         'locale' => nil,
                         'effective_locale' => 'en',
                         'k5_user' => false
                       })
  end

  it 'returns the correct locale if not using the system default' do
    @user = @student
    @student.locale = 'es'
    @student.save!
    json = api_call(:get, "/api/v1/users/#{@student.id}/profile",
                    :controller => "profile", :action => "settings", :user_id => @student.to_param, :format => 'json')
    expect(json).to eq({
                         'id' => @student.id,
                         'name' => 'Student',
                         'sortable_name' => 'Student',
                         'short_name' => 'Student',
                         'integration_id' => nil,
                         'primary_email' => 'pvuser@example.com',
                         'login_id' => 'pvuser@example.com',
                         'avatar_url' => default_avatar_url,
                         'calendar' => { 'ics' => "http://www.example.com/feeds/calendars/user_#{@student.uuid}.ics" },
                         'lti_user_id' => @student.lti_context_id,
                         'title' => nil,
                         'bio' => nil,
                         'time_zone' => 'Etc/UTC',
                         'locale' => 'es',
                         'effective_locale' => 'es',
                         'k5_user' => false
                       })
  end

  it "returns this user's profile (non-admin)" do
    @user = @student
    json = api_call(:get, "/api/v1/users/#{@student.id}/profile",
                    :controller => "profile", :action => "settings", :user_id => @student.to_param, :format => 'json')
    expect(json).to eq({
                         'id' => @student.id,
                         'name' => 'Student',
                         'sortable_name' => 'Student',
                         'short_name' => 'Student',
                         'integration_id' => nil,
                         'primary_email' => 'pvuser@example.com',
                         'login_id' => 'pvuser@example.com',
                         'avatar_url' => default_avatar_url,
                         'calendar' => { 'ics' => "http://www.example.com/feeds/calendars/user_#{@student.uuid}.ics" },
                         'lti_user_id' => @student.lti_context_id,
                         'title' => nil,
                         'bio' => nil,
                         'time_zone' => 'Etc/UTC',
                         'locale' => nil,
                         'effective_locale' => 'en',
                         'k5_user' => false
                       })
  end

  it "respects :read_email_addresses permission" do
    RoleOverride.create!(:context => Account.default, :permission => 'read_email_addresses',
                         :role => admin_role, :enabled => false)
    json = api_call(:get, "/api/v1/users/#{@student.id}/profile",
                    :controller => "profile", :action => "settings", :user_id => @student.to_param, :format => 'json')
    expect(json['id']).to eq @student.id
    expect(json['primary_email']).to be_nil
  end

  it "returns this user's avatars, if allowed" do
    @user = @student
    @student.register
    json = api_call(:get, "/api/v1/users/#{@student.id}/avatars",
                    :controller => "profile", :action => "profile_pics", :user_id => @student.to_param, :format => 'json')
    expect(json.map { |j| j['type'] }.sort).to eql ['gravatar', 'no_pic']
  end

  it "does not return disallowed profiles" do
    @user = @student
    raw_api_call(:get, "/api/v1/users/#{@admin.id}/profile",
                 :controller => "profile", :action => "settings", :user_id => @admin.to_param, :format => 'json')
    assert_status(401)
  end

  context "user_services" do
    before :once do
      @student.user_services.create! :service => 'skype', :service_user_name => 'user', :service_user_id => 'user', :visible => false
      @student.user_services.create! :service => 'twitter', :service_user_name => 'user', :service_user_id => 'user', :visible => true
      @student.user_services.create! :service => 'somethingthatdoesntexistanymore', :service_user_name => 'user', :service_user_id => 'user', :visible => true
    end

    before do
      allow(Twitter::Connection).to receive(:config).and_return({ :some_hash => "fullofstuff" })
    end

    it "returns user_services, if requested" do
      @user = @student
      json = api_call(:get, "/api/v1/users/#{@student.id}/profile?include[]=user_services",
                      :controller => "profile", :action => "settings",
                      :user_id => @student.to_param, :format => "json",
                      :include => ["user_services"])
      expect(json["user_services"]).to eq [
        { "service" => "skype", "visible" => false, "service_user_link" => "skype:user?add" },
        { "service" => "twitter", "visible" => true, "service_user_link" => "http://www.twitter.com/user" }
      ]
    end

    it "only returns visible services for other users" do
      @user = @admin
      json = api_call(:get, "/api/v1/users/#{@student.id}/profile?include[]=user_services",
                      :controller => "profile", :action => "settings",
                      :user_id => @student.to_param, :format => "json",
                      :include => %w(user_services))
      expect(json["user_services"]).to eq [
        { "service" => "twitter", "visible" => true, "service_user_link" => "http://www.twitter.com/user" },
      ]
    end

    it "returns profile links, if requested" do
      @student.profile.save
      @student.profile.links.create! :url => "http://instructure.com",
                                     :title => "Instructure"

      json = api_call(:get, "/api/v1/users/#{@student.id}/profile?include[]=links",
                      :controller => "profile", :action => "settings",
                      :user_id => @student.to_param, :format => "json",
                      :include => %w(links))
      expect(json["links"]).to eq [
        { "url" => "http://instructure.com", "title" => "Instructure" }
      ]
    end
  end

  context 'canvas for elementary' do
    it 'returns k5_user false if not a k5 user' do
      toggle_k5_setting(@course.account, false)

      @user = @student
      json = api_call(:get, "/api/v1/users/#{@student.id}/profile",
                      controller: "profile", action: "settings",
                      user_id: @student.to_param, format: "json")

      expect(json['k5_user']).to eq(false)
    end

    context 'k5 mode on' do
      before(:once) do
        toggle_k5_setting(@course.account, true)
      end

      it 'returns k5_user true for current_user' do
        @user = @student
        json = api_call(:get, "/api/v1/users/#{@student.id}/profile",
                        controller: "profile", action: "settings",
                        user_id: @student.to_param, format: "json")
        expect(json['k5_user']).to eq(true)
      end

      it 'returns k5_user nil for other users' do
        course_with_teacher(active_all: true, course: @course)
        @user = @teacher
        json = api_call(:get, "/api/v1/users/#{@student.id}/profile",
                        controller: "profile", action: "settings",
                        user_id: @student.to_param, format: "json")
        expect(json['k5_user']).to be_nil
      end
    end
  end
end
