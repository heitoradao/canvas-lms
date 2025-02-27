# frozen_string_literal: true

#
# Copyright (C) 2011 - present Instructure, Inc.
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

describe AvatarHelper do
  include AvatarHelper

  context "avatars" do
    let_once(:user) { user_model(short_name: "test user") }
    let(:services) { { avatars: true } }
    let(:avatar_size) { 50 }
    let(:request) { ActionDispatch::Request.new(Rack::MockRequest.env_for("http://test.host/")) }

    def service_enabled?(type)
      services[type]
    end

    describe ".avatar_image_attrs" do
      it "accepts a user id" do
        expect(self).to receive(:avatar_url_for_user).with(user).and_return("test_url")
        expect(avatar_image_attrs(user.id)).to eq ["test_url", user.short_name]
      end

      it "accepts a user" do
        expect(self).to receive(:avatar_url_for_user).with(user).and_return("test_url")
        expect(avatar_image_attrs(user)).to eq ["test_url", user.short_name]
      end

      it "falls back to blank avatar when given a user id of 0" do
        expect(avatar_image_attrs(0)).to eq ["/images/messages/avatar-50.png", '']
      end

      it "falls back to blank avatar when user's avatar has been reported during this session" do
        expect(self).to receive(:session).at_least(:once).and_return({ "reported_#{user.id}" => true })
        expect(avatar_image_attrs(user)).to eq ["/images/messages/avatar-50.png", '']
      end

      it "falls back to a blank avatar when the user is nil" do
        expect(avatar_image_attrs(nil)).to eq ["/images/messages/avatar-50.png", '']
      end
    end

    describe ".avatar" do
      let_once(:user) { user_model(short_name: 'Greta') }

      it "leaves off the href and creates a span if url is nil" do
        html = avatar(user, url: nil)
        expect(html).not_to match(/<a/)
        expect(html).to match(/<span/)
        expect(html).not_to match(/href/)
      end

      it "sets the href to the given url" do
        expect(avatar(user, url: "/test_url")).to match(/href="\/test_url"/)
      end

      it "links to the context user's page when given a context_code" do
        expect(self).to receive(:context_prefix).with('course_1').and_return('/courses/1')
        expect(avatar(user, context_code: "course_1")).to match("href=\"/courses/1/users/#{user.id}\"")
      end

      it "links to the user's page" do
        expect(avatar(user)).to match("/users/#{user.id}")
      end

      it "falls back to a blank avatar when the user is nil" do
        expect(avatar(nil)).to match("/images/messages/avatar-50.png")
      end

      it 'includes screenreader content if supplied' do
        text = avatar(user, sr_content: 'boogaloo')
        expect(text).to include("<span class=\"screenreader-only\">boogaloo</span>")
      end

      it 'defaults the screenreader content to just the display name if sr_content is not supplied' do
        text = avatar(user)
        expect(text).to include("<span class=\"screenreader-only\">Greta</span>")
      end
    end

    describe ".avatar_url_for_user" do
      before(:once) do
        Account.default.tap { |a|
          a.enable_service(:avatars)
          a.save!
        }
      end

      it "returns a fallback avatar if the user doesn't have one" do
        request = OpenObject.new(:host => "somedomain", :protocol => "http://")
        expect(AvatarHelper.avatar_url_for_user(user, request)).to eql "http://somedomain/images/messages/avatar-50.png"
      end

      it "returns null if use_fallback is false" do
        request = OpenObject.new(:host => "somedomain", :protocol => "http://")
        expect(AvatarHelper.avatar_url_for_user(user, request, use_fallback: false)).to be_nil
      end

      it "returns null if params[no_avatar_fallback] is set" do
        request = OpenObject.new(:host => "somedomain", :protocol => "http://", :params => { :no_avatar_fallback => 1 })
        expect(AvatarHelper.avatar_url_for_user(user, request)).to be_nil
      end

      it "returns a frd avatar url if one exists" do
        request = OpenObject.new(:host => "somedomain", :protocol => "http://", :params => { :no_avatar_fallback => 1 })
        user_with_avatar = user_model(avatar_image_url: 'http://somedomain/avatar-frd.png')
        expect(AvatarHelper.avatar_url_for_user(user_with_avatar, request, use_fallback: false)).to eq 'http://somedomain/avatar-frd.png'
      end

      it "does not prepend the request base if avatar url is an empty string" do
        request = OpenObject.new(:host => "somedomain", :protocol => "http://", :base_url => "http://somedomain")
        user = user_model(avatar_image_url: '')
        expect(AvatarHelper.avatar_url_for_user(user, request)).to eq ""
      end
    end

    context "with avatar service off" do
      let(:services) { { avatars: false } }

      it "returns full URIs for users" do
        expect(avatar_url_for_user(user)).to match(%r{\Ahttps?://})
      end
    end

    it "returns full URIs for users" do
      user_factory
      expect(avatar_url_for_user(@user)).to match(%r{\Ahttps?://})

      @user.account.set_service_availability(:avatars, true)
      @user.avatar_image_source = 'no_pic'
      @user.save!
      # reload to clear instance vars
      @user = User.find(@user.id)
      expect(avatar_url_for_user(@user)).to match(%r{\Ahttps?://})

      @user.avatar_state = 'approved'

      @user.avatar_image_source = 'attachment'
      @user.avatar_image_url = "/relative/canvas/path"
      @user.save!
      @user = User.find(@user.id)
      expect(avatar_url_for_user(@user)).to eq "http://test.host/relative/canvas/path"

      @user.avatar_image_source = 'external'
      @user.avatar_image_url = "http://www.example.com/path"
      @user.save!
      @user = User.find(@user.id)
      expect(avatar_url_for_user(@user)).to eq "http://www.example.com/path"
    end

    it "returns full URIs for groups" do
      expect(avatar_url_for_group).to match(%r{\Ahttps?://})
    end

    context "from other shard" do
      specs_require_sharding
      it "returns full path across shards" do
        @user.account.set_service_availability(:avatars, true)
        @user.avatar_image_source = 'attachment'
        @user.avatar_image_url = "/relative/canvas/path"
        @shard2.activate do
          expect(avatar_url_for_user(@user)).to eq "http://test.host/relative/canvas/path"
        end
      end
    end
  end
end
