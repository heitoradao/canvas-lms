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

describe ContextExternalTool do
  before(:once) do
    @root_account = Account.default
    @account = account_model(:root_account => @root_account, :parent_account => @root_account)
    course_model(:account => @account)
  end

  describe 'associations' do
    let_once(:developer_key) { DeveloperKey.create! }
    let_once(:tool) do
      ContextExternalTool.create!(
        context: @course,
        consumer_key: 'key',
        shared_secret: 'secret',
        name: 'test tool',
        url: 'http://www.tool.com/launch',
        developer_key: developer_key,
        root_account: @root_account
      )
    end

    it 'allows setting the developer key' do
      expect(tool.developer_key).to eq developer_key
    end

    it 'allows setting the root account' do
      expect(tool.root_account).to eq @root_account
    end
  end

  describe '#permission_given?' do
    let(:required_permission) { 'some-permission' }
    let(:launch_type) { 'some-launch-type' }
    let(:tool) do
      ContextExternalTool.create!(
        context: @root_account,
        name: 'Requires Permission',
        consumer_key: 'key',
        shared_secret: 'secret',
        domain: 'requires.permision.com',
        settings: {
          global_navigation: {
            'required_permissions' => required_permission,
            text: 'Global Navigation (permission checked)',
            url: 'http://requires.permission.com'
          },
          assignment_selection: {
            'required_permissions' => required_permission,
            text: 'Assignment selection',
            url: 'http://requires.permission.com'
          },
          course_navigation: {
            text: 'Course Navigation',
            url: 'https://doesnot.requirepermission.com'
          }
        }
      )
    end
    let(:course) { course_with_teacher(account: @root_account).context }
    let(:user) { course.teachers.first }
    let(:context) { course }

    subject { tool.permission_given?(launch_type, user, context) }

    context 'when the placement does not require a specific permission' do
      let(:launch_type) { 'course_navigation' }

      it { is_expected.to eq true }

      context 'and the context is blank' do
        let(:launch_type) { 'course_navigation' }
        let(:context) { nil }

        it { is_expected.to eq true }
      end
    end

    context 'when the placement does require a specific permission' do
      context 'and the context is blank' do
        let(:required_permission) { 'view_group_pages' }
        let(:launch_type) { 'assignment_selection' }
        let(:context) { nil }

        it { is_expected.to eq false }
      end

      context 'and the user has the needed permission in the context' do
        let(:required_permission) { 'view_group_pages' }
        let(:launch_type) { 'assignment_selection' }

        it { is_expected.to eq true }
      end

      context 'and the placement is "global_navigation"' do
        context 'and the user has an enrollment with the needed permission' do
          let(:required_permission) { 'view_group_pages' }
          let(:launch_type) { 'global_navigation' }

          it { is_expected.to eq true }
        end
      end
    end
  end

  describe "#global_navigation_tools" do
    subject do
      ContextExternalTool.filtered_global_navigation_tools(
        @root_account,
        granted_permissions
      )
    end

    let(:granted_permissions) {
      ContextExternalTool.global_navigation_granted_permissions(root_account: @root_account,
                                                                user: global_nav_user, context: global_nav_context, session: nil)
    }
    let(:global_nav_user) { nil }
    let(:global_nav_context) { nil }
    let(:required_permission) { 'some-permission' }

    let!(:permission_required_tool) do
      ContextExternalTool.create!(
        context: @root_account,
        name: 'Requires Permission',
        consumer_key: 'key',
        shared_secret: 'secret',
        domain: 'requires.permision.com',
        settings: {
          global_navigation: {
            'required_permissions' => required_permission,
            text: 'Global Navigation (permission checked)',
            url: 'http://requires.permission.com'
          }
        }
      )
    end
    let!(:no_permission_required_tool) do
      ContextExternalTool.create!(
        context: @root_account,
        name: 'No Requires Permission',
        consumer_key: 'key',
        shared_secret: 'secret',
        domain: 'no.requires.permision.com',
        settings: {
          global_navigation: {
            text: 'Global Navigation (no permission)',
            url: 'http://no.requries.permission.com'
          }
        }
      )
    end

    context 'when a user and context are provided' do
      let(:global_nav_user) { @course.teachers.first }
      let(:global_nav_context) { @course }

      context 'when the current user has the required permission' do
        let(:required_permission) { 'send_messages_all' }

        before { @course.update!(workflow_state: "created") }

        it { is_expected.to match_array [no_permission_required_tool, permission_required_tool] }
      end

      context 'when the current user does not have the required permission' do\
        it { is_expected.to match_array [no_permission_required_tool] }
      end
    end

    context 'when a user and context are not provided' do
      let(:required_permission) { nil }

      it { is_expected.to match_array [no_permission_required_tool, permission_required_tool] }
    end
  end

  describe '#login_or_launch_url' do
    let_once(:developer_key) { DeveloperKey.create! }
    let_once(:tool) do
      ContextExternalTool.create!(
        context: @course,
        consumer_key: 'key',
        shared_secret: 'secret',
        name: 'test tool',
        url: 'http://www.tool.com/launch',
        developer_key: developer_key
      )
    end

    it 'returns the launch url' do
      expect(tool.login_or_launch_url).to eq tool.url
    end

    context 'when a content_tag_uri is specified' do
      let(:content_tag_uri) { 'https://www.test.com/tool-launch' }

      it 'returns the content tag uri' do
        expect(tool.login_or_launch_url(content_tag_uri: content_tag_uri)).to eq content_tag_uri
      end
    end

    context 'when the extension url is present' do
      let(:placement_url) { 'http://www.test.com/editor_button' }

      before do
        tool.editor_button = {
          "url" => placement_url,
          "text" => "LTI 1.3 twoa",
          "enabled" => true,
          "icon_url" => "https://static.thenounproject.com/png/131630-200.png",
          "message_type" => "LtiDeepLinkingRequest",
          "canvas_icon_class" => "icon-lti"
        }
      end

      it 'returns the extension url' do
        expect(tool.login_or_launch_url(extension_type: :editor_button)).to eq placement_url
      end
    end

    context 'lti_1_3 tool' do
      let(:oidc_initiation_url) { 'http://www.test.com/oidc/login' }

      before do
        tool.settings['use_1_3'] = true
        developer_key.update!(oidc_initiation_url: oidc_initiation_url)
      end

      it 'returns the oidc login url' do
        expect(tool.login_or_launch_url).to eq oidc_initiation_url
      end
    end
  end

  describe '#deployment_id' do
    let_once(:tool) do
      ContextExternalTool.create!(
        id: 1,
        context: @course,
        consumer_key: 'key',
        shared_secret: 'secret',
        name: 'test tool',
        url: 'http://www.tool.com/launch'
      )
    end

    it 'returns the correct deployment_id' do
      expect(tool.deployment_id).to eq "#{tool.id}:#{Lti::Asset.opaque_identifier_for(tool.context)}"
    end

    it 'sends only 255 chars' do
      allow(Lti::Asset).to receive(:opaque_identifier_for).and_return(256.times.map { 'a' }.join)
      expect(tool.deployment_id.size).to eq 255
    end
  end

  describe '#matches_host?' do
    subject { tool.matches_host?(given_url) }

    let(:tool) { external_tool_model }
    let(:given_url) { 'https://www.given-url.com/test?foo=bar' }

    context 'when the tool has a url and no domain' do
      let(:url) { 'https://app.test.com/foo' }

      before do
        tool.update!(
          domain: nil,
          url: url
        )
      end

      context 'and the tool url host does not match that of the given url host' do
        it { is_expected.to eq false }
      end

      context 'and the tool url host matches that of the given url host' do
        let(:url) { 'https://www.given-url.com/foo?foo=bar' }

        it { is_expected.to eq true }
      end

      context 'and the tool url host matches except for case' do
        let(:url) { 'https://www.GiveN-url.cOm/foo?foo=bar' }

        it { is_expected.to eq true }
      end
    end

    context 'when the tool has a domain and no url' do
      let(:domain) { 'app.test.com' }

      before do
        tool.update!(
          url: nil,
          domain: domain
        )
      end

      context 'and the tool domain host does not match that of the given url host' do
        it { is_expected.to eq false }

        context 'and the tool url and given url are both nil' do
          let(:given_url) { nil }

          it { is_expected.to eq false }
        end
      end

      context 'and the tool domain host matches that of the given url host' do
        let(:domain) { 'www.given-url.com' }

        it { is_expected.to eq true }
      end

      context 'and the tool domain matches except for case' do
        let(:domain) { 'www.gIvEn-URL.cOm' }

        it { is_expected.to eq true }
      end

      context 'and the tool domain contains the protocol' do
        let(:domain) { 'https://www.given-url.com' }

        it { is_expected.to eq true }
      end

      context 'and the domain and given URL contain a port' do
        let(:domain) { 'localhost:3001' }
        let(:given_url) { 'http://localhost:3001/link_location' }

        it { is_expected.to eq true }
      end
    end
  end

  describe '#duplicated_in_context?' do
    shared_examples_for 'detects duplication in contexts' do
      subject { second_tool.duplicated_in_context? }
      let(:context) { raise 'Override in spec' }
      let(:second_tool) { tool.dup }
      let(:settings) do
        {
          "editor_button" => {
            "icon_url" => "http://www.example.com/favicon.ico",
            "text" => "Example",
            "url" => "http://www.example.com",
            "selection_height" => 400,
            "selection_width" => 600
          }
        }
      end
      let(:tool) do
        ContextExternalTool.create!(
          settings: settings,
          context: context,
          name: 'first tool',
          consumer_key: 'key',
          shared_secret: 'secret',
          url: 'http://www.tool.com/launch'
        )
      end

      context 'when url is not set' do
        let(:domain) { 'instructure.com' }

        before { tool.update!(url: nil, domain: domain) }

        context 'when no other tools are installed in the context' do
          it 'does not count as duplicate' do
            expect(tool.duplicated_in_context?).to eq false
          end
        end

        context 'when a tool with matching domain is found' do
          it { is_expected.to eq true }
        end

        context 'when a tool with matching domain is found in different context' do
          before { second_tool.update!(context: course_model) }

          it { is_expected.to eq false }
        end

        context 'when a tool with matching domain is not found' do
          before { second_tool.domain = 'different-domain.com' }

          it { is_expected.to eq false }
        end
      end

      context 'when no other tools are installed in the context' do
        it 'does not count as duplicate' do
          expect(tool.duplicated_in_context?).to eq false
        end
      end

      context 'when a tool with matching settings and different URL is found' do
        before { second_tool.url << '/different/url' }

        it { is_expected.to eq false }
      end

      context 'when a tool with different settings and matching URL is found' do
        before { second_tool.settings[:different_key] = 'different value' }

        it { is_expected.to eq true }
      end

      context 'when a tool with different settings and different URL is found' do
        before do
          second_tool.url << '/different/url'
          second_tool.settings[:different_key] = 'different value'
        end

        it { is_expected.to eq false }
      end

      context 'when a tool with matching settings and matching URL is found' do
        it { is_expected.to eq true }
      end
    end

    context 'duplicated in account chain' do
      it_behaves_like 'detects duplication in contexts' do
        let(:context) { account_model }
      end
    end

    context 'duplicated in course' do
      it_behaves_like 'detects duplication in contexts' do
        let(:context) { course_model }
      end
    end
  end

  describe '#content_migration_configured?' do
    let(:tool) do
      ContextExternalTool.new.tap do |t|
        t.settings = {
          'content_migration' => {
            'export_start_url' => 'https://lti.example.com/begin_export',
            'import_start_url' => 'https://lti.example.com/begin_import',
          }
        }
      end
    end

    it 'must return false when the content_migration key is missing from the settings hash' do
      tool.settings.delete('content_migration')
      expect(tool.content_migration_configured?).to eq false
    end

    it 'must return false when the content_migration key is present in the settings hash but the export_start_url sub key is missing' do
      tool.settings['content_migration'].delete('export_start_url')
      expect(tool.content_migration_configured?).to eq false
    end

    it 'must return false when the content_migration key is present in the settings hash but the import_start_url sub key is missing' do
      tool.settings['content_migration'].delete('import_start_url')
      expect(tool.content_migration_configured?).to eq false
    end

    it 'must return true when the content_migration key and all relevant sub-keys are present' do
      expect(tool.content_migration_configured?).to eq true
    end
  end

  describe "url or domain validation" do
    it "validates with a domain setting" do
      @tool = @course.context_external_tools.create(:name => "a", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      expect(@tool).not_to be_new_record
      expect(@tool.errors).to be_empty
    end

    it "validates with a url setting" do
      @tool = @course.context_external_tools.create(:name => "a", :url => "http://google.com", :consumer_key => '12345', :shared_secret => 'secret')
      expect(@tool).not_to be_new_record
      expect(@tool.errors).to be_empty
    end

    it "validates with a canvas lti extension url setting" do
      @tool = @course.context_external_tools.new(:name => "a", :consumer_key => '12345', :shared_secret => 'secret')
      @tool.editor_button = {
        "icon_url" => "http://www.example.com/favicon.ico",
        "text" => "Example",
        "url" => "http://www.example.com",
        "selection_height" => 400,
        "selection_width" => 600
      }
      @tool.save
      expect(@tool).not_to be_new_record
      expect(@tool.errors).to be_empty
    end

    def url_test(nav_url = nil)
      course_with_teacher(:active_all => true)
      @tool = @course.context_external_tools.new(:name => "a", :consumer_key => '12345', :shared_secret => 'secret', :url => "http://www.example.com")
      Lti::ResourcePlacement::PLACEMENTS.each do |type|
        @tool.send "#{type}=", {
          :url => nav_url,
          :text => "Example",
          :icon_url => "http://www.example.com/image.ico",
          :selection_width => 50,
          :selection_height => 50
        }

        launch_url = @tool.extension_setting(type, :url)

        if nav_url
          expect(launch_url).to eq nav_url
        else
          expect(launch_url).to eq @tool.url
        end
      end
    end

    it "allows extension to not have a url if the main config has a url" do
      url_test
    end

    it "prefers the extension url to the main config url" do
      url_test("https://example.com/special_launch_of_death")
    end

    it "does not allow extension with no custom url and a domain match" do
      @tool = @course.context_external_tools.create!(:name => "a", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tool.course_navigation = {
        :text => "Example"
      }
      @tool.save!
      expect(@tool.has_placement?(:course_navigation)).to eq false
    end

    it "does not validate with no domain or url setting" do
      @tool = @course.context_external_tools.create(:name => "a", :consumer_key => '12345', :shared_secret => 'secret')
      expect(@tool).to be_new_record
      expect(@tool.errors['url']).to eq ["Either the url or domain should be set."]
      expect(@tool.errors['domain']).to eq ["Either the url or domain should be set."]
    end

    it "accepts both a domain and a url" do
      @tool = @course.context_external_tools.create(:name => "a", :domain => "google.com", :url => "http://google.com", :consumer_key => '12345', :shared_secret => 'secret')
      expect(@tool).not_to be_new_record
      expect(@tool.errors).to be_empty
    end
  end

  it "allows extension with only 'enabled' key" do
    @tool = @course.context_external_tools.create!(:name => "a", :url => "http://google.com", :consumer_key => '12345', :shared_secret => 'secret')
    @tool.course_navigation = {
      :enabled => "true"
    }
    @tool.save!
    expect(@tool.has_placement?(:course_navigation)).to eq true
  end

  it "allows accept_media_types setting exclusively for file_menu extension" do
    @tool = @course.context_external_tools.create!(:name => "a", :url => "http://google.com", :consumer_key => '12345', :shared_secret => 'secret')
    @tool.course_navigation = {
      :accept_media_types => "types"
    }
    @tool.file_menu = {
      :accept_media_types => "types"
    }
    @tool.save!
    expect(@tool.extension_setting(:course_navigation, :accept_media_types)).to be_blank
    expect(@tool.extension_setting(:file_menu, :accept_media_types)).to eq "types"
  end

  it "clears disabled extensions" do
    @tool = @course.context_external_tools.create!(:name => "a", :url => "http://google.com", :consumer_key => '12345', :shared_secret => 'secret')
    @tool.course_navigation = {
      :enabled => "false"
    }
    @tool.save!
    expect(@tool.has_placement?(:course_navigation)).to eq false
  end

  describe 'validate_urls' do
    subject { tool.valid? }

    let(:tool) do
      course.context_external_tools.build(
        :name => "a", :url => url, :consumer_key => '12345', :shared_secret => 'secret', settings: settings
      )
    end
    let(:settings) { {} }
    let_once(:course) { course_model }
    let(:url) { 'https://example.com' }

    context 'with bad launch_url' do
      let(:url) { 'https://example.com>' }

      it { is_expected.to be false }
    end

    context 'with bad settings_url' do
      let(:settings) do
        { course_navigation: {
          :url => 'https://example.com>',
          :text => "Example",
          :icon_url => "http://www.example.com/image.ico",
          :selection_width => 50,
          :selection_height => 50
        } }
      end

      it { is_expected.to be false }
    end
  end

  describe "active?" do
    subject { tool.active? }

    let(:tool) { external_tool_model(opts: tool_opts) }
    let(:tool_opts) { {} }

    it { is_expected.to eq true }

    context 'when "workflow_state" is "deleted"' do
      let(:tool_opts) { { workflow_state: 'deleted' } }

      it { is_expected.to eq false }
    end

    context 'when "workflow_state" is "disabled"' do
      let(:tool_opts) { { workflow_state: 'disabled' } }

      it { is_expected.to eq false }
    end
  end

  describe "uses_preferred_lti_version?" do
    subject { tool.uses_preferred_lti_version? }

    let_once(:tool) { external_tool_model }

    it { is_expected.to eq false }

    context 'when the tool uses LTI 1.3' do
      before do
        tool.use_1_3 = true
        tool.save!
      end

      it { is_expected.to eq true }
    end
  end

  describe "from_content_tag" do
    subject { ContextExternalTool.from_content_tag(*arguments) }

    let(:arguments) { [content_tag, tool.context] }
    let(:assignment) { assignment_model(course: tool.context) }
    let(:tool) { external_tool_model }
    let(:content_tag_opts) { { url: tool.url, content_type: 'ContextExternalTool', context: assignment } }
    let(:content_tag) { ContentTag.new(content_tag_opts) }

    let(:lti_1_3_tool) do
      t = tool.dup
      t.use_1_3 = true
      t.save!
      t
    end

    it { is_expected.to eq tool }

    context 'when the tool is linked to the tag by id (LTI 1.1)' do
      let(:content_tag_opts) { super().merge({ content_id: tool.id }) }

      it { is_expected.to eq tool }

      context 'and an LTI 1.3 tool has a conflicting URL' do
        let(:arguments) do
          [content_tag, tool.context]
        end

        before { lti_1_3_tool }

        it { is_expected.to be_use_1_3 }
      end
    end

    context 'when the tool is linked to a tag by id (LTI 1.3)' do
      let(:content_tag_opts) { super().merge({ content_id: lti_1_3_tool.id }) }
      let(:duplicate_1_3_tool) do
        t = lti_1_3_tool.dup
        t.save!
        t
      end

      context 'and an LTI 1.1 tool has a conflicting URL' do
        before { tool } # intitialized already, but included for clarity

        it { is_expected.to eq lti_1_3_tool }

        context 'and there are multiple matching LTI 1.3 tools' do
          before { duplicate_1_3_tool }

          let(:arguments) { [content_tag, tool.context] }
          let(:content_tag_opts) { super().merge({ content_id: lti_1_3_tool.id }) }

          it { is_expected.to eq lti_1_3_tool }
        end

        context 'and the LTI 1.3 tool gets reinstalled' do
          before do
            # "install" a copy of the tool
            duplicate_1_3_tool

            # "uninstall" the original tool
            lti_1_3_tool.destroy!
          end

          it { is_expected.to eq duplicate_1_3_tool }
        end
      end
    end

    context 'when there are blank arguments' do
      context 'when the content tag argument is blank' do
        let(:arguments) { [nil, tool.context] }

        it { is_expected.to eq nil }
      end

      context 'when the context argument is blank' do
        let(:arguments) { [nil, tool.context] }

        it { is_expected.to eq nil }
      end
    end
  end

  describe "find_external_tool" do
    it "matches on the same domain" do
      @tool = @course.context_external_tools.create!(:name => "a", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://google.com/is/cool", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "is case insensitive when matching on the same domain" do
      @tool = @course.context_external_tools.create!(:name => "a", :domain => "Google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://google.com/is/cool", Course.find(@course.id), @tool.id)
      expect(@found_tool).to eql(@tool)
    end

    it "matches on a subdomain" do
      @tool = @course.context_external_tools.create!(:name => "a", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com/is/cool", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "matches on a domain with a scheme attached" do
      @tool = @course.context_external_tools.create!(:name => "a", :domain => "http://google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com/is/cool", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "does not match on non-matching domains" do
      @tool = @course.context_external_tools.create!(:name => "a", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tool2 = @course.context_external_tools.create!(:name => "a", :domain => "www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://mgoogle.com/is/cool", Course.find(@course.id))
      expect(@found_tool).to eql(nil)
      @found_tool = ContextExternalTool.find_external_tool("http://sgoogle.com/is/cool", Course.find(@course.id))
      expect(@found_tool).to eql(nil)
    end

    it "does not match on the closest matching domain" do
      @tool = @course.context_external_tools.create!(:name => "a", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tool2 = @course.context_external_tools.create!(:name => "a", :domain => "www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.www.google.com/is/cool", Course.find(@course.id))
      expect(@found_tool).to eql(@tool2)
    end

    it "matches on exact url" do
      @tool = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com/coolness", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com/coolness", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "matches on url ignoring query parameters" do
      @tool = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com/coolness", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com/coolness?a=1", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com/coolness?a=1&b=2", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "matches on url even when tool url contains query parameters" do
      @tool = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com/coolness?a=1&b=2", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com/coolness?b=2&a=1", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com/coolness?c=3&b=2&d=4&a=1", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "does not match on url if the tool url contains query parameters that the search url doesn't" do
      @tool = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com/coolness?a=1", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com/coolness?a=2", Course.find(@course.id))
      expect(@found_tool).to be_nil
    end

    it "does not match on url before matching on domain" do
      @tool = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com/coolness", :consumer_key => '12345', :shared_secret => 'secret')
      @tool2 = @course.context_external_tools.create!(:name => "a", :domain => "www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com/coolness", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "does not match on domain if domain is nil" do
      @tool = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com/coolness", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://malicious.domain./hahaha", Course.find(@course.id))
      expect(@found_tool).to be_nil
    end

    it "matches on url or domain for a tool that has both" do
      @tool = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com/coolness", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      expect(ContextExternalTool.find_external_tool("http://google.com/is/cool", Course.find(@course.id))).to eql(@tool)
      expect(ContextExternalTool.find_external_tool("http://www.google.com/coolness", Course.find(@course.id))).to eql(@tool)
    end

    it "finds the context's tool matching on url first" do
      @tool = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @course.context_external_tools.create!(:name => "b", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @account.context_external_tools.create!(:name => "c", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @account.context_external_tools.create!(:name => "d", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @root_account.context_external_tools.create!(:name => "e", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @root_account.context_external_tools.create!(:name => "f", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "finds the nearest account's tool matching on url if there are no url-matching context tools" do
      @course.context_external_tools.create!(:name => "b", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tool = @account.context_external_tools.create!(:name => "c", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @account.context_external_tools.create!(:name => "d", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @root_account.context_external_tools.create!(:name => "e", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @root_account.context_external_tools.create!(:name => "f", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "finds the root account's tool matching on url before matching by domain on the course" do
      @course.context_external_tools.create!(:name => "b", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @account.context_external_tools.create!(:name => "d", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tool = @root_account.context_external_tools.create!(:name => "e", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @root_account.context_external_tools.create!(:name => "f", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "finds the context's tool matching on domain if no url-matching tools are found" do
      @tool = @course.context_external_tools.create!(:name => "b", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @account.context_external_tools.create!(:name => "d", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @root_account.context_external_tools.create!(:name => "f", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "finds the nearest account's tool matching on domain if no url-matching tools are found" do
      @tool = @account.context_external_tools.create!(:name => "c", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @root_account.context_external_tools.create!(:name => "e", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    it "finds the root account's tool matching on domain if no url-matching tools are found" do
      @tool = @root_account.context_external_tools.create!(:name => "e", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @found_tool = ContextExternalTool.find_external_tool("http://www.google.com/", Course.find(@course.id))
      expect(@found_tool).to eql(@tool)
    end

    context 'when exclude_tool_id is set' do
      subject { ContextExternalTool.find_external_tool("http://www.google.com", Course.find(course.id), nil, exclude_tool.id) }

      let(:course) { @course }
      let(:exclude_tool) do
        course.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      end

      it 'does not return the excluded tool' do
        expect(subject).to be_nil
      end
    end

    context 'preferred_tool_id' do
      it "finds the preferred tool if there are two matching-priority tools" do
        @tool1 = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @tool2 = @course.context_external_tools.create!(:name => "b", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id), @tool1.id)
        expect(@found_tool).to eql(@tool1)
        @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id), @tool2.id)
        expect(@found_tool).to eql(@tool2)
        @tool1.destroy
        @tool2.destroy

        @tool1 = @course.context_external_tools.create!(:name => "a", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @tool2 = @course.context_external_tools.create!(:name => "b", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id), @tool1.id)
        expect(@found_tool).to eql(@tool1)
        @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id), @tool2.id)
        expect(@found_tool).to eql(@tool2)
      end

      it "finds the preferred tool even if there is a higher priority tool configured" do
        @tool = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @preferred = @root_account.context_external_tools.create!(:name => "f", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')

        @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id), @preferred.id)
        expect(@found_tool).to eql(@preferred)
      end

      it "does not find the preferred tool if it is deleted" do
        @preferred = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @preferred.destroy
        @course.context_external_tools.create!(:name => "b", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @tool = @account.context_external_tools.create!(:name => "c", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @account.context_external_tools.create!(:name => "d", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @root_account.context_external_tools.create!(:name => "e", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @root_account.context_external_tools.create!(:name => "f", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id), @preferred.id)
        expect(@found_tool).to eql(@tool)
      end

      it "does not find the preferred tool if it is disabled" do
        @preferred = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @preferred.update!(workflow_state: 'disabled')
        @course.context_external_tools.create!(:name => "b", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @tool = @account.context_external_tools.create!(:name => "c", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @account.context_external_tools.create!(:name => "d", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @root_account.context_external_tools.create!(:name => "e", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @root_account.context_external_tools.create!(:name => "f", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
        @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id), @preferred.id)
        expect(@found_tool).to eql(@tool)
      end

      it "does not return preferred tool outside of context chain" do
        preferred = @root_account.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        expect(ContextExternalTool.find_external_tool("http://www.google.com", @course, preferred.id)).to eq preferred
      end

      it "does not return preferred tool if url doesn't match" do
        c1 = @course
        preferred = c1.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        expect(ContextExternalTool.find_external_tool("http://example.com", c1, preferred.id)).to be_nil
      end

      it "returns the preferred tool if the url is nil" do
        c1 = @course
        preferred = c1.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
        expect(ContextExternalTool.find_external_tool(nil, c1, preferred.id)).to eq preferred
      end

      it "does not return preferred tool if it is 1.1 and there is a matching 1.3 tool" do
        @tool1_1 = @course.context_external_tools.create!(name: "a", url: "http://www.google.com", consumer_key: '12345', shared_secret: 'secret')
        @tool1_3 = @course.context_external_tools.create!(name: "b", url: "http://www.google.com", consumer_key: '12345', shared_secret: 'secret')
        @tool1_3.settings[:use_1_3] = true
        @tool1_3.save!

        @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id), @tool1_1.id)
        expect(@found_tool).to eql(@tool1_3)
        @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id), @tool1_3.id)
        expect(@found_tool).to eql(@tool1_3)
        @tool1_1.destroy
        @tool1_3.destroy

        @tool1_1 = @course.context_external_tools.create!(name: "a", domain: "google.com", consumer_key: '12345', shared_secret: 'secret')
        @tool1_3 = @course.context_external_tools.create!(name: "b", domain: "google.com", consumer_key: '12345', shared_secret: 'secret')
        @tool1_3.settings[:use_1_3] = true
        @tool1_3.save!
        @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id), @tool1_1.id)
        expect(@found_tool).to eql(@tool1_3)
        @found_tool = ContextExternalTool.find_external_tool("http://www.google.com", Course.find(@course.id), @tool1_3.id)
        expect(@found_tool).to eql(@tool1_3)
      end
    end

    context 'when multiple ContextExternalTools have domain/url conflict' do
      before do
        ContextExternalTool.create!(
          context: @course,
          consumer_key: 'key1',
          shared_secret: 'secret1',
          name: 'test faked tool',
          url: 'http://nothing',
          domain: 'www.tool.com',
          tool_id: 'faked'
        )

        ContextExternalTool.create!(
          context: @course,
          consumer_key: 'key2',
          shared_secret: 'secret2',
          name: 'test tool',
          url: 'http://www.tool.com/launch',
          tool_id: 'real'
        )
      end

      it 'picks up url in higher priority' do
        tool = ContextExternalTool.find_external_tool('http://www.tool.com/launch?p1=2082', Course.find(@course.id))
        expect(tool.tool_id).to eq('real')
      end

      context 'and there is a difference in LTI version' do
        subject { ContextExternalTool.find_external_tool(requested_url, context) }

        before do
          # Creation order is important. Be default Canvas uses
          # creation order as a tie-breaker. Creating the LTI 1.3
          # tool first ensures we are actually exercising the preferred
          # LTI version matching logic.
          lti_1_1_tool
          lti_1_3_tool
        end

        let(:context) { @course }
        let(:domain) { 'www.test.com' }
        let(:opts) { { url: url, domain: domain } }
        let(:requested_url) { "" }
        let(:url) { 'https://www.test.com/foo?bar=1' }
        let(:lti_1_1_tool) { external_tool_model(context: context, opts: opts) }
        let(:lti_1_3_tool) do
          t = external_tool_model(context: context, opts: opts)
          t.use_1_3 = true
          t.save!
          t
        end

        context 'with an exact URL match' do
          let(:requested_url) { url }

          it { is_expected.to eq lti_1_3_tool }
        end

        context 'with a partial URL match' do
          let(:requested_url) { "#{url}&extra_param=1" }

          it { is_expected.to eq lti_1_3_tool }
        end

        context 'whith a domain match' do
          let(:requested_url) { "https://www.test.com/another_endpoint" }

          it { is_expected.to eq lti_1_3_tool }
        end
      end
    end

    context('with a client id') do
      let(:url) { 'http://test.com' }
      let(:tool_params) do
        {
          name: "a",
          url: url,
          consumer_key: '12345',
          shared_secret: 'secret',
        }
      end
      let!(:tool1) { @course.context_external_tools.create!(tool_params) }
      let!(:tool2) do
        @course.context_external_tools.create!(
          tool_params.merge(developer_key: DeveloperKey.create!)
        )
      end

      it 'preferred_tool_id has precedence over preferred_client_id' do
        external_tool = ContextExternalTool.find_external_tool(
          url, @course, tool1.id, nil, tool2.developer_key.id
        )
        expect(external_tool).to eq tool1
      end

      it 'finds the tool based on developer key id' do
        external_tool = ContextExternalTool.find_external_tool(
          url, @course, nil, nil, tool2.developer_key.id
        )
        expect(external_tool).to eq tool2
      end
    end
  end

  describe "#extension_setting" do
    it "returns the top level extension setting if no placement is given" do
      tool = @course.context_external_tools.new(:name => "bob",
                                                :consumer_key => "bob",
                                                :shared_secret => "bob")
      tool.url = "http://www.example.com/basic_lti"
      tool.settings[:windowTarget] = "_blank"
      tool.save!
      expect(tool.extension_setting(nil, :windowTarget)).to eq '_blank'
    end
  end

  describe "custom fields" do
    it "parses custom_fields_string from a text field" do
      tool = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      tool.custom_fields_string = ("a=1\nbT^@!#n_40=123\n\nc=")
      expect(tool.custom_fields).not_to be_nil
      expect(tool.custom_fields.keys.length).to eq 2
      expect(tool.custom_fields['a']).to eq '1'
      expect(tool.custom_fields['bT^@!#n_40']).to eq '123'
      expect(tool.custom_fields['c']).to eq nil
    end

    it "returns custom_fields_string as a text-formatted field" do
      tool = @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret', :custom_fields => { 'a' => '123', 'b' => '456' })
      fields_string = tool.custom_fields_string
      expect(fields_string).to eq "a=123\nb=456"
    end

    it "merges custom fields for extension launches" do
      course_with_teacher(:active_all => true)
      @tool = @course.context_external_tools.new(:name => "a", :consumer_key => '12345', :shared_secret => 'secret', :custom_fields => { 'a' => "1", 'b' => "2" }, :url => "http://www.example.com")
      Lti::ResourcePlacement::PLACEMENTS.each do |type|
        @tool.send "#{type}=", {
          :text => "Example",
          :url => "http://www.example.com",
          :icon_url => "http://www.example.com/image.ico",
          :custom_fields => { "b" => "5", "c" => "3" },
          :selection_width => 50,
          :selection_height => 50
        }
        @tool.save!

        hash = @tool.set_custom_fields(type)
        expect(hash["custom_a"]).to eq "1"
        expect(hash["custom_b"]).to eq "5"
        expect(hash["custom_c"]).to eq "3"

        @tool.settings[type.to_sym][:custom_fields] = nil
        hash = @tool.set_custom_fields(type)

        expect(hash["custom_a"]).to eq "1"
        expect(hash["custom_b"]).to eq "2"
        expect(hash).not_to have_key("custom_c")
      end
    end
  end

  describe "all_tools_for" do
    it "retrieves all tools in alphabetical order" do
      @tools = []
      @tools << @root_account.context_external_tools.create!(:name => "f", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tools << @root_account.context_external_tools.create!(:name => "e", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tools << @account.context_external_tools.create!(:name => "d", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tools << @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tools << @course.context_external_tools.create!(:name => "b", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tools << @account.context_external_tools.create!(:name => "c", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret')
      expect(ContextExternalTool.all_tools_for(@course).to_a).to eql(@tools.sort_by(&:name))
    end

    it "returns all tools that are selectable" do
      @tools = []
      @tools << @root_account.context_external_tools.create!(:name => "f", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tools << @root_account.context_external_tools.create!(:name => "e", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret', not_selectable: true)
      @tools << @account.context_external_tools.create!(:name => "d", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tools << @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret', not_selectable: true)
      tools = ContextExternalTool.all_tools_for(@course, selectable: true)
      expect(tools.count).to eq 2
    end

    it 'returns multiple requested placements' do
      tool1 = @course.context_external_tools.create!(:name => "First Tool", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
      tool2 = @course.context_external_tools.new(:name => "Another Tool", :consumer_key => "key", :shared_secret => "secret")
      tool2.settings[:editor_button] = { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 }.with_indifferent_access
      tool2.save!
      tool3 = @course.context_external_tools.new(:name => "Third Tool", :consumer_key => "key", :shared_secret => "secret")
      tool3.settings[:resource_selection] = { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 }.with_indifferent_access
      tool3.save!
      placements = Lti::ResourcePlacement::LEGACY_DEFAULT_PLACEMENTS + ['resource_selection']
      expect(ContextExternalTool.all_tools_for(@course, placements: placements).to_a).to eql([tool1, tool3].sort_by(&:name))
    end

    it 'honors only_visible option' do
      course_with_student(active_all: true, user: user_with_pseudonym, account: @account)
      @tools = []
      @tools << @root_account.context_external_tools.create!(:name => "f", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tools << @course.context_external_tools.create!(:name => "d", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret',
                                                       :settings => { :assignment_view => { :visibility => 'admins' } })
      @tools << @course.context_external_tools.create!(:name => "a", :url => "http://www.google.com", :consumer_key => '12345', :shared_secret => 'secret',
                                                       :settings => { :assignment_view => { :visibility => 'members' } })
      tools = ContextExternalTool.all_tools_for(@course)
      expect(tools.count).to eq 3
      tools = ContextExternalTool.all_tools_for(@course, only_visible: true, current_user: @user, visibility_placements: ["assignment_view"])
      expect(tools.count).to eq 1
      expect(tools[0].name).to eq 'a'
    end
  end

  describe "placements" do
    it 'returns multiple requested placements' do
      tool1 = @course.context_external_tools.create!(:name => "First Tool", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
      tool2 = @course.context_external_tools.new(:name => "Another Tool", :consumer_key => "key", :shared_secret => "secret")
      tool2.settings[:editor_button] = { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 }.with_indifferent_access
      tool2.save!
      tool3 = @course.context_external_tools.new(:name => "Third Tool", :consumer_key => "key", :shared_secret => "secret")
      tool3.settings[:resource_selection] = { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 }.with_indifferent_access
      tool3.save!
      placements = Lti::ResourcePlacement::LEGACY_DEFAULT_PLACEMENTS + ['resource_selection']
      expect(ContextExternalTool.all_tools_for(@course).placements(*placements).to_a).to eql([tool1, tool3].sort_by(&:name))
    end

    it 'only returns a single requested placements' do
      @course.context_external_tools.create!(:name => "First Tool", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
      tool2 = @course.context_external_tools.new(:name => "Another Tool", :consumer_key => "key", :shared_secret => "secret")
      tool2.settings[:editor_button] = { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 }.with_indifferent_access
      tool2.save!
      tool3 = @course.context_external_tools.new(:name => "Third Tool", :consumer_key => "key", :shared_secret => "secret")
      tool3.settings[:resource_selection] = { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 }.with_indifferent_access
      tool3.save!
      expect(ContextExternalTool.all_tools_for(@course).placements('resource_selection').to_a).to eql([tool3])
    end

    it "doesn't return not selectable tools placements for moudle_item" do
      tool1 = @course.context_external_tools.create!(:name => "First Tool", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
      tool2 = @course.context_external_tools.new(:name => "Another Tool", :consumer_key => "key", :shared_secret => "secret")
      tool2.settings[:editor_button] = { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 }.with_indifferent_access
      tool2.save!
      tool3 = @course.context_external_tools.new(:name => "Third Tool", :consumer_key => "key", :shared_secret => "secret")
      tool3.settings[:resource_selection] = { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 }.with_indifferent_access
      tool3.not_selectable = true
      tool3.save!
      expect(ContextExternalTool.all_tools_for(@course).placements(*Lti::ResourcePlacement::LEGACY_DEFAULT_PLACEMENTS).to_a).to eql([tool1])
    end

    context 'when passed the legacy default placements' do
      it "doesn't return tools with a developer key (LTI 1.3 tools)" do
        tool1 = @course.context_external_tools.create!(
          :name => "First Tool", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret"
        )
        @course.context_external_tools.create!(
          :name => "First Tool", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret", :developer_key => DeveloperKey.create!
        )
        expect(ContextExternalTool.all_tools_for(@course).placements(*Lti::ResourcePlacement::LEGACY_DEFAULT_PLACEMENTS).to_a).to eql([tool1])
      end
    end

    describe 'enabling/disabling placements' do
      let!(:tool) {
        tool = @course.context_external_tools.create!(:name => "First Tool", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
        tool.homework_submission = { enabled: true, selection_height: 300 }
        tool.save
        tool
      }

      it 'moves inactive placement data back to active when re-enabled' do
        tool.homework_submission = { enabled: false }
        expect(tool.settings[:inactive_placements][:homework_submission][:enabled]).to be_falsey

        tool.homework_submission = { enabled: true }
        expect(tool.settings[:homework_submission]).to include({ enabled: true, selection_height: 300 })
        expect(tool.settings).not_to have_key(:inactive_placements)
      end

      it 'moves placement data to inactive placements when disabled' do
        tool.homework_submission = { enabled: false }
        expect(tool.settings[:inactive_placements][:homework_submission]).to include({ enabled: false, selection_height: 300 })
        expect(tool.settings).not_to have_key(:homework_submission)
      end

      it 'keeps already inactive placement data when disabled again' do
        tool.homework_submission = { enabled: false }
        expect(tool.settings[:inactive_placements][:homework_submission]).to include({ enabled: false, selection_height: 300 })

        tool.homework_submission = { enabled: false }
        expect(tool.settings[:inactive_placements][:homework_submission]).to include({ enabled: false, selection_height: 300 })
      end

      it 'keeps already active placement data when enabled again' do
        tool.homework_submission = { enabled: true }
        expect(tool.settings[:homework_submission]).to include({ enabled: true, selection_height: 300 })
      end

      it 'toggles not_selectable when placement is resource_selection' do
        tool.resource_selection = { enabled: true }

        tool.resource_selection = { enabled: false }
        tool.save
        expect(tool.not_selectable).to be_truthy

        tool.resource_selection = { enabled: true }
        tool.save
        expect(tool.not_selectable).to be_falsy
      end
    end
  end

  describe "visible" do
    it "returns all tools to admins" do
      course_with_teacher(active_all: true, user: user_with_pseudonym, account: @account)
      tool1 = @course.context_external_tools.create!(:name => "1", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
      tool2 = @course.context_external_tools.new(:name => "2", :consumer_key => "key", :shared_secret => "secret")
      tool2.settings[:assignment_view] = { :url => "http://www.example.com" }.with_indifferent_access
      tool2.save!
      expect(ContextExternalTool.all_tools_for(@course).visible(@user, @course, nil, []).to_a).to eql([tool1, tool2].sort_by(&:name))
    end

    it "returns nothing if a non-admin requests without specifying placement" do
      course_with_student(active_all: true, user: user_with_pseudonym, account: @account)
      @course.context_external_tools.create!(:name => "1", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
      tool2 = @course.context_external_tools.new(:name => "2", :consumer_key => "key", :shared_secret => "secret")
      tool2.settings[:assignment_view] = { :url => "http://www.example.com" }.with_indifferent_access
      tool2.save!
      expect(ContextExternalTool.all_tools_for(@course).visible(@user, @course, nil, []).to_a).to eql([])
    end

    it "returns only tools with placements matching the requested placement" do
      course_with_student(active_all: true, user: user_with_pseudonym, account: @account)
      @course.context_external_tools.create!(:name => "1", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
      tool2 = @course.context_external_tools.new(:name => "2", :consumer_key => "key", :shared_secret => "secret")
      tool2.settings[:assignment_view] = { :url => "http://www.example.com" }.with_indifferent_access
      tool2.save!
      expect(ContextExternalTool.all_tools_for(@course).visible(@user, @course, nil, ["assignment_view"]).to_a).to eql([tool2])
    end

    it "does not return admin tools to students" do
      course_with_student(active_all: true, user: user_with_pseudonym, account: @account)
      tool = @course.context_external_tools.create!(:name => "1", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
      tool.settings[:assignment_view] = { :url => "http://www.example.com", :visibility => 'admins' }.with_indifferent_access
      tool.save!
      expect(ContextExternalTool.all_tools_for(@course).visible(@user, @course, nil, ["assignment_view"]).to_a).to eql([])
    end

    it "does return member tools to students" do
      course_with_student(active_all: true, user: user_with_pseudonym, account: @account)
      tool = @course.context_external_tools.create!(:name => "1", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
      tool.settings[:assignment_view] = { :url => "http://www.example.com", :visibility => 'members' }.with_indifferent_access
      tool.save!
      expect(ContextExternalTool.all_tools_for(@course).visible(@user, @course, nil, ["assignment_view"]).to_a).to eql([tool])
    end

    it "does not return member tools to public" do
      tool = @course.context_external_tools.create!(:name => "1", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
      tool.settings[:assignment_view] = { :url => "http://www.example.com", :visibility => 'members' }.with_indifferent_access
      tool.save!
      expect(ContextExternalTool.all_tools_for(@course).visible(nil, @course, nil, ["assignment_view"]).to_a).to eql([])
    end

    it "does return public tools to public" do
      tool = @course.context_external_tools.create!(:name => "1", :url => "http://www.example.com", :consumer_key => "key", :shared_secret => "secret")
      tool.settings[:assignment_view] = { :url => "http://www.example.com", :visibility => 'public' }.with_indifferent_access
      tool.save!
      expect(ContextExternalTool.all_tools_for(@course).visible(nil, @course, nil, ["assignment_view"]).to_a).to eql([tool])
    end
  end

  describe "infer_defaults" do
    def new_external_tool
      @root_account.context_external_tools.new(:name => "t", :consumer_key => '12345', :shared_secret => 'secret', :domain => "google.com")
    end

    context "setting the root account" do
      let(:new_tool) do
        context.context_external_tools.new(
          name: 'test',
          consumer_key: 'key',
          shared_secret: 'secret',
          domain: 'www.test.com'
        )
      end

      shared_examples_for 'a tool that infers the root account' do
        let(:context) { raise 'set "context" in examples' }

        it 'sets the root account' do
          expect { new_tool.save! }.to change { new_tool.root_account }.from(nil).to context.root_account
        end
      end

      context 'when the context is a course' do
        it_behaves_like 'a tool that infers the root account' do
          let(:context) { course_model }
        end
      end

      context 'when the context is an account' do
        it_behaves_like 'a tool that infers the root account' do
          let(:context) { account_model }
        end
      end
    end

    it "requires valid configuration for user navigation settings" do
      tool = new_external_tool
      tool.settings = { :user_navigation => { :bob => 'asfd' } }
      tool.save
      expect(tool.user_navigation).to be_nil
      tool.settings = { :user_navigation => { :url => "http://www.example.com" } }
      tool.save
      expect(tool.user_navigation).not_to be_nil
    end

    it "requires valid configuration for course navigation settings" do
      tool = new_external_tool
      tool.settings = { :course_navigation => { :bob => 'asfd' } }
      tool.save
      expect(tool.course_navigation).to be_nil
      tool.settings = { :course_navigation => { :url => "http://www.example.com" } }
      tool.save
      expect(tool.course_navigation).not_to be_nil
    end

    it "requires valid configuration for account navigation settings" do
      tool = new_external_tool
      tool.settings = { :account_navigation => { :bob => 'asfd' } }
      tool.save
      expect(tool.account_navigation).to be_nil
      tool.settings = { :account_navigation => { :url => "http://www.example.com" } }
      tool.save
      expect(tool.account_navigation).not_to be_nil
    end

    it "requires valid configuration for resource selection settings" do
      tool = new_external_tool
      tool.settings = { :resource_selection => { :bob => 'asfd' } }
      tool.save
      expect(tool.resource_selection).to be_nil
      tool.settings = { :resource_selection => { :url => "http://www.example.com", :selection_width => 100, :selection_height => 100 } }
      tool.save
      expect(tool.resource_selection).not_to be_nil
    end

    it "requires valid configuration for editor button settings" do
      tool = new_external_tool
      tool.settings = { :editor_button => { :bob => 'asfd' } }
      tool.save
      expect(tool.editor_button).to be_nil
      tool.settings = { :editor_button => { :url => "http://www.example.com" } }
      tool.save
      expect(tool.editor_button).to be_nil
      tool.settings = { :editor_button => { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 } }
      tool.save
      expect(tool.editor_button).not_to be_nil
    end

    it "sets user_navigation if navigation configured" do
      tool = new_external_tool
      tool.settings = { :user_navigation => { :url => "http://www.example.com" } }
      expect(tool.has_placement?(:user_navigation)).to be_falsey
      tool.save
      expect(tool.has_placement?(:user_navigation)).to be_truthy
    end

    it "sets course_navigation if navigation configured" do
      tool = new_external_tool
      tool.settings = { :course_navigation => { :url => "http://www.example.com" } }
      expect(tool.has_placement?(:course_navigation)).to be_falsey
      tool.save
      expect(tool.has_placement?(:course_navigation)).to be_truthy
    end

    it "sets account_navigation if navigation configured" do
      tool = new_external_tool
      tool.settings = { :account_navigation => { :url => "http://www.example.com" } }
      expect(tool.has_placement?(:account_navigation)).to be_falsey
      tool.save
      expect(tool.has_placement?(:account_navigation)).to be_truthy
    end

    it "sets resource_selection if selection configured" do
      tool = new_external_tool
      tool.settings = { :resource_selection => { :url => "http://www.example.com", :selection_width => 100, :selection_height => 100 } }
      expect(tool.has_placement?(:resource_selection)).to be_falsey
      tool.save
      expect(tool.has_placement?(:resource_selection)).to be_truthy
    end

    it "sets editor_button if button configured" do
      tool = new_external_tool
      tool.settings = { :editor_button => { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 } }
      expect(tool.has_placement?(:editor_button)).to be_falsey
      tool.save
      expect(tool.has_placement?(:editor_button)).to be_truthy
    end

    it "removes and add placements according to configuration" do
      tool = new_external_tool
      tool.settings = {
        :editor_button => { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 },
        :resource_selection => { :url => "http://www.example.com", :selection_width => 100, :selection_height => 100 }
      }
      tool.save!
      expect(tool.context_external_tool_placements.pluck(:placement_type)).to match_array(['editor_button', 'resource_selection'])
      tool.settings.delete(:editor_button)
      tool.settings[:account_navigation] = { :url => "http://www.example.com" }
      tool.save!
      expect(tool.context_external_tool_placements.pluck(:placement_type)).to match_array(['resource_selection', 'account_navigation'])
    end

    it "allows setting tool_id and icon_url" do
      tool = new_external_tool
      tool.tool_id = "new_tool"
      tool.icon_url = "http://www.example.com/favicon.ico"
      tool.save
      expect(tool.tool_id).to eq "new_tool"
      expect(tool.icon_url).to eq "http://www.example.com/favicon.ico"
    end
  end

  describe "extension settings" do
    let(:tool) do
      tool = @root_account.context_external_tools.new({ :name => "t", :consumer_key => '12345', :shared_secret => 'secret', :url => "http://google.com/launch_url" })
      tool.settings = { :selection_width => 100, :selection_height => 100, :icon_url => "http://www.example.com/favicon.ico" }
      tool.save
      tool
    end

    it "gets the tools launch url if no extension urls are configured" do
      tool.editor_button = { :enabled => true }
      tool.save
      expect(tool.editor_button(:url)).to eq "http://google.com/launch_url"
    end

    it "falls back to tool defaults" do
      tool.editor_button = { :url => "http://www.example.com" }
      tool.save
      expect(tool.editor_button).not_to eq nil
      expect(tool.editor_button(:url)).to eq "http://www.example.com"
      expect(tool.editor_button(:icon_url)).to eq "http://www.example.com/favicon.ico"
      expect(tool.editor_button(:selection_width)).to eq 100
    end

    it "returns nil if the tool is not enabled" do
      expect(tool.resource_selection).to eq nil
      expect(tool.resource_selection(:url)).to eq nil
    end

    it "gets properties for each tool extension" do
      tool.course_navigation = { :enabled => true }
      tool.account_navigation = { :enabled => true }
      tool.user_navigation = { :enabled => true }
      tool.resource_selection = { :enabled => true }
      tool.editor_button = { :enabled => true }
      tool.save
      expect(tool.course_navigation).not_to eq nil
      expect(tool.account_navigation).not_to eq nil
      expect(tool.user_navigation).not_to eq nil
      expect(tool.resource_selection).not_to eq nil
      expect(tool.editor_button).not_to eq nil
    end

    context 'placement enabled setting' do
      context 'when placement has enabled defined' do
        before do
          tool.course_navigation = { enabled: false }
          tool.save
        end

        it 'includes enabled from placement' do
          expect(tool.course_navigation[:enabled]).to be false
        end
      end

      context 'when placement does not have enabled defined' do
        before do
          tool.course_navigation = { text: 'hello world' }
        end

        it "includes enabled: true" do
          expect(tool.course_navigation[:enabled]).to be true
        end
      end
    end

    describe "display_type" do
      it "is 'in_context' by default" do
        expect(tool.display_type(:course_navigation)).to eq 'in_context'
        tool.course_navigation = { enabled: true }
        tool.save!
        expect(tool.display_type(:course_navigation)).to eq 'in_context'
      end

      it "is configurable by a property" do
        tool.course_navigation = { enabled: true }
        tool.settings[:display_type] = "custom_display_type"
        tool.save!
        expect(tool.display_type(:course_navigation)).to eq 'custom_display_type'
      end

      it "is configurable in extension" do
        tool.course_navigation = { display_type: 'other_display_type' }
        tool.save!
        expect(tool.display_type(:course_navigation)).to eq 'other_display_type'
      end
    end

    describe "validation" do
      def set_visibility(v)
        tool.file_menu = { enabled: true, visibility: v }
        tool.save!
        tool.reload
      end

      context "when visibility is included in placement config" do
        it 'accepts `admins`' do
          set_visibility('admins')
          expect(tool.file_menu[:visibility]).to eq 'admins'
        end

        it 'accepts `members`' do
          set_visibility('members')
          expect(tool.file_menu[:visibility]).to eq 'members'
        end

        it 'accepts `public`' do
          set_visibility('public')
          expect(tool.file_menu[:visibility]).to eq 'public'
        end

        it 'does not accept any other values' do
          set_visibility('public')
          set_visibility('fake')
          expect(tool.file_menu[:visibility]).to eq 'public'
        end

        it 'accepts `nil` and removes visibility' do
          set_visibility('members')
          set_visibility(nil)
          expect(tool.file_menu).not_to have_key(:visibility)
        end
      end
    end
  end

  describe '#setting_with_default_enabled' do
    let(:tool) do
      t = external_tool_model(context: @root_account)
      t.settings = settings
      t.save
      t
    end

    subject do
      tool.setting_with_default_enabled(type)
    end

    context 'when settings does not contain type' do
      let(:settings) { { oauth_compliant: true } }
      let(:type) { :course_navigation }

      it 'returns nil' do
        expect(subject).to be_nil
      end
    end

    context 'when settings contains type' do
      context 'when type is not a placement' do
        let(:settings) { { oauth_compliant: true } }
        let(:type) { :oauth_compliant }

        it 'returns settings[type]' do
          expect(subject).to eq settings[type]
        end
      end

      context 'when type is a placement' do
        let(:type) { :course_navigation }

        context 'when type configuration defines `enabled`' do
          let(:settings) do
            {
              course_navigation: { enabled: false, text: 'hello world' }
            }
          end

          it 'returns settings[type]' do
            expect(subject).to eq settings[type].with_indifferent_access
          end
        end

        context 'when type configuration does not define `enabled`' do
          let(:settings) do
            {
              course_navigation: { text: 'hello world' }
            }
          end

          it 'returns settings[type] with enabled: true' do
            expect(subject[:enabled]).to be true
            expect(subject.except(:enabled)).to eq settings[type].with_indifferent_access
          end
        end
      end
    end
  end

  describe "#extension_default_value" do
    it "returns resource_selection when the type is 'resource_slection'" do
      expect(subject.extension_default_value(:resource_selection, :message_type)).to eq 'resource_selection'
    end
  end

  describe "change_domain" do
    let(:prod_base_url) { 'http://www.example.com' }
    let(:new_host) { 'test.example.com' }

    let(:tool) do
      tool = @root_account.context_external_tools.new(:name => "bob", :consumer_key => "bob", :shared_secret => "bob", :domain => "www.example.com", :url => prod_base_url)
      tool.settings = { :url => prod_base_url, :icon_url => "#{prod_base_url}/icon.ico" }
      tool.account_navigation = { :url => "#{prod_base_url}/launch?my_var=1" }
      tool.editor_button = { :url => "#{prod_base_url}/resource_selection", :icon_url => "#{prod_base_url}/resource_selection.ico" }
      tool
    end

    it "updates the domain" do
      tool.change_domain! new_host
      expect(tool.domain).to eq new_host
      expect(URI.parse(tool.url).host).to eq new_host
      expect(URI.parse(tool.settings[:url]).host).to eq new_host
      expect(URI.parse(tool.icon_url).host).to eq new_host
      expect(URI.parse(tool.account_navigation[:url]).host).to eq new_host
      expect(URI.parse(tool.editor_button[:url]).host).to eq new_host
      expect(URI.parse(tool.editor_button[:icon_url]).host).to eq new_host
    end

    it "ignores domain if it is nil" do
      tool.domain = nil
      tool.change_domain! new_host
      expect(tool.domain).to be_nil
    end

    it "ignores launch url if it is nil" do
      tool.url = nil
      tool.change_domain! new_host
      expect(tool.url).to be_nil
    end

    it "ignores custom fields" do
      tool.custom_fields = { :url => 'http://www.google.com/' }
      tool.change_domain! new_host
      expect(tool.custom_fields[:url]).to eq 'http://www.google.com/'
    end

    it "ignores environments fields" do
      tool.settings["environments"] = { :launch_url => 'http://www.google.com/' }
      tool.change_domain! new_host
      expect(tool.settings["environments"]).to eq({ :launch_url => 'http://www.google.com/' })
    end

    it "ignores an existing invalid url" do
      tool.url = "null"
      tool.change_domain! new_host
      expect(tool.url).to eq "null"
    end
  end

  describe "standardize_url" do
    it "standardizes urls" do
      url = ContextExternalTool.standardize_url("http://www.google.com?a=1&b=2")
      expect(url).to eql(ContextExternalTool.standardize_url("http://www.google.com?b=2&a=1"))
      expect(url).to eql(ContextExternalTool.standardize_url("http://www.google.com/?b=2&a=1"))
      expect(url).to eql(ContextExternalTool.standardize_url("www.google.com/?b=2&a=1"))
    end

    it 'handles spaces in front of url' do
      url = ContextExternalTool.standardize_url(" http://sub_underscore.google.com?a=1&b=2")
      expect(url).to eql('http://sub_underscore.google.com/?a=1&b=2')
    end

    it 'handles tabs in front of url' do
      url = ContextExternalTool.standardize_url("\thttp://sub_underscore.google.com?a=1&b=2")
      expect(url).to eql('http://sub_underscore.google.com/?a=1&b=2')
    end

    it 'handles unicode whitespace' do
      url = ContextExternalTool.standardize_url("\u00A0http://sub_underscore.go\u2005ogle.com?a=1\u2002&b=2")
      expect(url).to eql('http://sub_underscore.google.com/?a=1&b=2')
    end

    it 'handles underscores in the domain' do
      url = ContextExternalTool.standardize_url("http://sub_underscore.google.com?a=1&b=2")
      expect(url).to eql('http://sub_underscore.google.com/?a=1&b=2')
    end
  end

  describe "default_label" do
    append_before do
      @tool = @root_account.context_external_tools.new(:consumer_key => '12345', :shared_secret => 'secret', :url => "http://example.com", :name => "tool name")
    end

    it "returns the default label if no language or name is specified" do
      expect(@tool.default_label).to eq 'tool name'
    end

    it "returns the localized label if a locale is specified" do
      @tool.settings = { :url => "http://example.com", :text => 'course nav', :labels => { 'en-US' => 'english nav' } }
      @tool.save!
      expect(@tool.default_label('en-US')).to eq 'english nav'
    end
  end

  describe "label_for" do
    append_before do
      @tool = @root_account.context_external_tools.new(:name => 'tool', :consumer_key => '12345', :shared_secret => 'secret', :url => "http://example.com")
    end

    it "returns the tool name if nothing else is configured and no key is sent" do
      @tool.save!
      expect(@tool.label_for(nil)).to eq 'tool'
    end

    it "returns the tool name if nothing is configured on the sent key" do
      @tool.settings = { :course_navigation => { :bob => 'asfd' } }
      @tool.save!
      expect(@tool.label_for(:course_navigation)).to eq 'tool'
    end

    it "returns the tool's 'text' value if no key is sent" do
      @tool.settings = { :text => 'tool label', :course_navigation => { :url => "http://example.com", :text => 'course nav' } }
      @tool.save!
      expect(@tool.label_for(nil)).to eq 'tool label'
    end

    it "returns the tool's 'text' value if no 'text' value is set for the sent key" do
      @tool.settings = { :text => 'tool label', :course_navigation => { :bob => 'asdf' } }
      @tool.save!
      expect(@tool.label_for(:course_navigation)).to eq 'tool label'
    end

    it "returns the tool's locale-specific 'text' value if no 'text' value is set for the sent key" do
      @tool.settings = { :text => 'tool label', :labels => { 'en' => 'translated tool label' }, :course_navigation => { :bob => 'asdf' } }
      @tool.save!
      expect(@tool.label_for(:course_navigation, 'en')).to eq 'translated tool label'
    end

    it "returns the setting's 'text' value for the sent key if available" do
      @tool.settings = { :text => 'tool label', :course_navigation => { :url => "http://example.com", :text => 'course nav' } }
      @tool.save!
      expect(@tool.label_for(:course_navigation)).to eq 'course nav'
    end

    it "returns the locale-specific label if specified and matching exactly" do
      @tool.settings = { :text => 'tool label', :course_navigation => { :url => "http://example.com", :text => 'course nav', :labels => { 'en-US' => 'english nav' } } }
      @tool.save!
      expect(@tool.label_for(:course_navigation, 'en-US')).to eq 'english nav'
      expect(@tool.label_for(:course_navigation, 'es')).to eq 'course nav'
    end

    it "returns the locale-specific label if specified and matching based on general locale" do
      @tool.settings = { :text => 'tool label', :course_navigation => { :url => "http://example.com", :text => 'course nav', :labels => { 'en' => 'english nav' } } }
      @tool.save!
      expect(@tool.label_for(:course_navigation, 'en-US')).to eq 'english nav'
    end
  end

  describe "find_for" do
    before :once do
      course_model
    end

    def new_external_tool(context)
      context.context_external_tools.new(:name => "bob", :consumer_key => "bob", :shared_secret => "bob", :domain => "google.com")
    end

    it "finds the tool if it's attached to the course" do
      tool = new_external_tool @course
      tool.course_navigation = { :url => "http://www.example.com", :text => "Example URL" }
      tool.save!
      expect(ContextExternalTool.find_for(tool.id, @course, :course_navigation)).to eq tool
      expect { ContextExternalTool.find_for(tool.id, @course, :user_navigation) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "finds the tool if it's attached to the course's account" do
      tool = new_external_tool @course.account
      tool.course_navigation = { :url => "http://www.example.com", :text => "Example URL" }
      tool.save!
      expect(ContextExternalTool.find_for(tool.id, @course, :course_navigation)).to eq tool
      expect { ContextExternalTool.find_for(tool.id, @course, :user_navigation) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "finds the tool if it's attached to the course's root account" do
      tool = new_external_tool @course.root_account
      tool.course_navigation = { :url => "http://www.example.com", :text => "Example URL" }
      tool.save!
      expect(ContextExternalTool.find_for(tool.id, @course, :course_navigation)).to eq tool
      expect { ContextExternalTool.find_for(tool.id, @course, :user_navigation) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does not find the tool if it's attached to a sub-account" do
      @account = @course.account.sub_accounts.create!(:name => "sub-account")
      tool = new_external_tool @account
      tool.course_navigation = { :url => "http://www.example.com", :text => "Example URL" }
      tool.save!
      expect { ContextExternalTool.find_for(tool.id, @course, :course_navigation) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does not find the tool if it's attached to another course" do
      @course2 = @course
      @course = course_model
      tool = new_external_tool @course2
      tool.course_navigation = { :url => "http://www.example.com", :text => "Example URL" }
      tool.save!
      expect { ContextExternalTool.find_for(tool.id, @course, :course_navigation) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does not find the tool if it's not enabled for the correct navigation type" do
      tool = new_external_tool @course
      tool.course_navigation = { :url => "http://www.example.com", :text => "Example URL" }
      tool.save!
      expect { ContextExternalTool.find_for(tool.id, @course, :user_navigation) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "raises RecordNotFound if the id is invalid" do
      expect { ContextExternalTool.find_for("horseshoes", @course, :course_navigation) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does not find a course tool with workflow_state deleted" do
      tool = new_external_tool @course
      tool.course_navigation = { :url => "http://www.example.com", :text => "Example URL" }
      tool.workflow_state = 'deleted'
      tool.save!
      expect { ContextExternalTool.find_for(tool.id, @course, :course_navigation) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it "does not find an account tool with workflow_state deleted" do
      tool = new_external_tool @account
      tool.account_navigation = { :url => "http://www.example.com", :text => "Example URL" }
      tool.workflow_state = 'deleted'
      tool.save!
      expect { ContextExternalTool.find_for(tool.id, @account, :account_navigation) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    context 'when the workflow state is "disabled"' do
      let(:tool) do
        tool = new_external_tool @account
        tool.account_navigation = { :url => "http://www.example.com", :text => "Example URL" }
        tool.workflow_state = 'disabled'
        tool.save!
        tool
      end

      it "does not find an account tool with workflow_state disabled" do
        expect { ContextExternalTool.find_for(tool.id, @account, :account_navigation) }.to raise_error(ActiveRecord::RecordNotFound)
      end

      context 'when the tool is installed in a course' do
        let(:tool) do
          tool = new_external_tool @course
          tool.course_navigation = { :url => "http://www.example.com", :text => "Example URL" }
          tool.workflow_state = 'disabled'
          tool.save!
          tool
        end

        it "does not find a course tool with workflow_state disabled" do
          expect { ContextExternalTool.find_for(tool.id, @course, :course_navigation) }.to raise_error(ActiveRecord::RecordNotFound)
        end
      end
    end
  end

  describe "opaque_identifier_for" do
    context 'when the asset is nil' do
      subject { ContextExternalTool.opaque_identifier_for(nil, Shard.first) }

      it { is_expected.to be_nil }
    end

    it "creates lti_context_id for asset" do
      expect(@course.lti_context_id).to eq nil
      @tool = @course.context_external_tools.create!(:name => "a", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      context_id = @tool.opaque_identifier_for(@course)
      @course.reload
      expect(@course.lti_context_id).to eq context_id
    end

    it "does not create new lti_context for asset if exists" do
      @course.lti_context_id = 'dummy_context_id'
      @course.save!
      @tool = @course.context_external_tools.create!(:name => "a", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      @tool.opaque_identifier_for(@course)
      @course.reload
      expect(@course.lti_context_id).to eq 'dummy_context_id'
    end

    it 'uses the global_asset_id for new assets that are stored in the db' do
      expect(@course.lti_context_id).to eq nil
      @tool = @course.context_external_tools.create!(:name => "a", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
      context_id = Lti::Asset.global_context_id_for(@course)
      @tool.opaque_identifier_for(@course)
      @course.reload
      expect(@course.lti_context_id).to eq context_id
    end
  end

  describe "global navigation" do
    before(:once) do
      @account = account_model
    end

    it "lets account admins see admin tools" do
      account_admin_user(:account => @account, :active_all => true)
      expect(ContextExternalTool.global_navigation_granted_permissions(
        root_account: @account, user: @user, context: @account
      )[:original_visibility]).to eq 'admins'
    end

    it "lets teachers see admin tools" do
      course_with_teacher(:account => @account, :active_all => true)
      expect(ContextExternalTool.global_navigation_granted_permissions(
        root_account: @account, user: @user, context: @account
      )[:original_visibility]).to eq 'admins'
    end

    it "does not let concluded teachers see admin tools" do
      course_with_teacher(:account => @account, :active_all => true)
      term = @course.enrollment_term
      term.enrollment_dates_overrides.create!(enrollment_type: "TeacherEnrollment", end_at: 1.week.ago, context: term.root_account)
      expect(ContextExternalTool.global_navigation_granted_permissions(
        root_account: @account, user: @user, context: @account
      )[:original_visibility]).to eq 'members'
    end

    it "does not let students see admin tools" do
      course_with_student(:account => @account, :active_all => true)
      expect(ContextExternalTool.global_navigation_granted_permissions(
        root_account: @account, user: @user, context: @account
      )[:original_visibility]).to eq 'members'
    end

    it "updates the visibility cache if enrollments are updated or user is touched" do
      time = Time.now
      enable_cache(:redis_cache_store) do
        Timecop.freeze(time) do
          course_with_student(:account => @account, :active_all => true)
          expect(ContextExternalTool.global_navigation_granted_permissions(
            root_account: @account, user: @user, context: @account
          )[:original_visibility]).to eq 'members'
        end

        Timecop.freeze(time + 1.second) do
          course_with_teacher(:account => @account, :active_all => true, :user => @user)
          expect(ContextExternalTool.global_navigation_granted_permissions(
            root_account: @account, user: @user, context: @account
          )[:original_visibility]).to eq 'admins'
        end

        Timecop.freeze(time + 2.second) do
          @user.teacher_enrollments.update_all(:workflow_state => 'deleted')
          # should not have affected the earlier cache
          expect(ContextExternalTool.global_navigation_granted_permissions(
            root_account: @account, user: @user, context: @account
          )[:original_visibility]).to eq 'admins'

          @user.clear_cache_key(:enrollments)
          expect(ContextExternalTool.global_navigation_granted_permissions(
            root_account: @account, user: @user, context: @account
          )[:original_visibility]).to eq 'members'
        end
      end
    end

    it "updates the global navigation menu cache key when the global navigation tools are updated (or removed)" do
      time = Time.now
      enable_cache do
        Timecop.freeze(time) do
          @admin_tool = @account.context_external_tools.new(:name => "a", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
          @admin_tool.global_navigation = { :visibility => 'admins', :url => "http://www.example.com", :text => "Example URL" }
          @admin_tool.save!
          @member_tool = @account.context_external_tools.new(:name => "b", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')
          @member_tool.global_navigation = { :url => "http://www.example.com", :text => "Example URL" }
          @member_tool.save!
          @other_tool = @account.context_external_tools.create!(:name => "c", :domain => "google.com", :consumer_key => '12345', :shared_secret => 'secret')

          @admin_cache_key = ContextExternalTool.global_navigation_menu_render_cache_key(@account, { :original_visibility => 'admins' })
          @member_cache_key = ContextExternalTool.global_navigation_menu_render_cache_key(@account, { :original_visibility => 'members' })
        end

        Timecop.freeze(time + 1.second) do
          @other_tool.save!
          # cache keys should remain the same
          expect(ContextExternalTool.global_navigation_menu_render_cache_key(@account, { :original_visibility => 'admins' })).to eq @admin_cache_key
          expect(ContextExternalTool.global_navigation_menu_render_cache_key(@account, { :original_visibility => 'members' })).to eq @member_cache_key
        end

        Timecop.freeze(time + 2.second) do
          @admin_tool.global_navigation = nil
          @admin_tool.save!
          # should update the admin key
          expect(ContextExternalTool.global_navigation_menu_render_cache_key(@account, { :original_visibility => 'admins' })).not_to eq @admin_cache_key
          # should not update the members key
          expect(ContextExternalTool.global_navigation_menu_render_cache_key(@account, { :original_visibility => 'members' })).to eq @member_cache_key
        end
      end
    end

    describe "#has_placement?" do
      it 'returns true for module item if it has selectable, and a url' do
        tool = @course.context_external_tools.create!(:name => "a", :url => "http://google.com", :consumer_key => '12345', :shared_secret => 'secret')
        expect(tool.has_placement?(:link_selection)).to eq true
      end

      it 'returns true for module item if it has selectable, and a domain' do
        tool = @course.context_external_tools.create!(:name => "a", :domain => "http://google.com", :consumer_key => '12345', :shared_secret => 'secret')
        expect(tool.has_placement?(:link_selection)).to eq true
      end

      it 'does not assume default placements for LTI 1.3 tools' do
        tool = @course.context_external_tools.create!(
          :name => "a", :domain => "http://google.com", :consumer_key => '12345', :shared_secret => 'secret', developer_key: DeveloperKey.create!
        )
        expect(tool.has_placement?(:link_selection)).to eq false
      end

      it 'returns false for module item if it is not selectable' do
        tool = @course.context_external_tools.create!(:name => "a", not_selectable: true, :url => "http://google.com", :consumer_key => '12345', :shared_secret => 'secret')
        expect(tool.has_placement?(:link_selection)).to eq false
      end

      it 'returns false for module item if it has selectable, and no domain or url' do
        tool = @course.context_external_tools.new(:name => "a", :consumer_key => '12345', :shared_secret => 'secret')
        tool.settings[:resource_selection] = { :url => "http://www.example.com", :icon_url => "http://www.example.com", :selection_width => 100, :selection_height => 100 }.with_indifferent_access
        tool.save!
        expect(tool.has_placement?(:link_selection)).to eq false
      end
    end

    describe ".find_tool_for_assignment" do
      let(:tool) do
        @course.context_external_tools.create(
          name: "a",
          consumer_key: '12345',
          shared_secret: 'secret',
          url: 'http://example.com/launch'
        )
      end

      it 'finds the tool from an assignment' do
        a = @course.assignments.create!(title: "test",
                                        submission_types: 'external_tool',
                                        external_tool_tag_attributes: { url: tool.url })
        expect(described_class.tool_for_assignment(a)).to eq tool
      end

      it 'returns nil if there is no content tag' do
        a = @course.assignments.create!(title: "test",
                                        submission_types: 'external_tool')
        expect(described_class.tool_for_assignment(a)).to be_nil
      end
    end

    describe ".visible?" do
      let(:u) { user_factory }
      let(:admin) { account_admin_user(account: c.root_account) }
      let(:c) { course_factory(active_course: true) }
      let(:student) do
        student = factory_with_protected_attributes(User, valid_user_attributes)
        e = c.enroll_student(student)
        e.invite
        e.accept
        student
      end
      let(:teacher) do
        teacher = factory_with_protected_attributes(User, valid_user_attributes)
        e = c.enroll_teacher(teacher)
        e.invite
        e.accept
        teacher
      end

      it 'returns true for public visibility' do
        expect(described_class.visible?('public', u, c)).to be true
      end

      it 'returns false for non members if visibility is members' do
        expect(described_class.visible?('members', u, c)).to be false
      end

      it 'returns true for members visibility if a student in the course' do
        expect(described_class.visible?('members', student, c)).to be true
      end

      it 'returns true for members visibility if a teacher in the course' do
        expect(described_class.visible?('members', teacher, c)).to be true
      end

      it 'returns true for admins visibility if a teacher' do
        expect(described_class.visible?('admins', teacher, c)).to be true
      end

      it 'returns true for admins visibility if an admin' do
        expect(described_class.visible?('admins', admin, c)).to be true
      end

      it 'returns false for admins visibility if a student' do
        expect(described_class.visible?('admins', student, c)).to be false
      end

      it 'returns false for admins visibility if a non member user' do
        expect(described_class.visible?('admins', u, c)).to be false
      end

      it 'returns true if visibility is invalid' do
        expect(described_class.visible?('true', u, c)).to be true
      end

      it 'returns true if visibility is nil' do
        expect(described_class.visible?(nil, u, c)).to be true
      end
    end

    describe '#feature_flag_enabled?' do
      let(:tool) do
        analytics_2_tool_factory
      end

      it 'returns true if the feature is enabled in context' do
        @course.enable_feature!(:analytics_2)
        expect(tool.feature_flag_enabled?(@course)).to be true
      end

      it 'returns true if the feature is enabled in higher context' do
        Account.default.enable_feature!(:analytics_2)
        expect(tool.feature_flag_enabled?(@course)).to be true
      end

      it 'checks the feature flag in the tool context if none provided' do
        Account.default.enable_feature!(:analytics_2)
        expect(tool.feature_flag_enabled?).to be true
      end

      it 'returns false if the feature is disabled' do
        expect(tool.feature_flag_enabled?(@course)).to be false
        expect(tool.feature_flag_enabled?).to be false
      end

      it "returns true if called on tools that aren't mapped to feature flags" do
        other_tool = @course.context_external_tools.create!(
          name: 'other_feature',
          consumer_key: 'key',
          shared_secret: 'secret',
          url: 'http://example.com/launch',
          tool_id: 'yo'
        )
        expect(other_tool.feature_flag_enabled?).to be true
      end
    end

    describe 'set_policy' do
      let(:tool) do
        @course.context_external_tools.create(
          name: "a",
          consumer_key: '12345',
          shared_secret: 'secret',
          url: 'http://example.com/launch'
        )
      end

      it 'grants update_manually to the proper individuals' do
        @admin = account_admin_user()

        course_with_teacher(:active_all => true, :account => Account.default)
        @teacher = user_factory(active_all: true)
        @course.enroll_teacher(@teacher).accept!

        @designer = user_factory(active_all: true)
        @course.enroll_designer(@designer).accept!

        @ta = user_factory(active_all: true)
        @course.enroll_ta(@ta).accept!

        @student = user_factory(active_all: true)
        @course.enroll_student(@student).accept!

        expect(tool.grants_right?(@admin, :update_manually)).to be_truthy
        expect(tool.grants_right?(@teacher, :update_manually)).to be_truthy
        expect(tool.grants_right?(@designer, :update_manually)).to be_truthy
        expect(tool.grants_right?(@ta, :update_manually)).to be_truthy
        expect(tool.grants_right?(@student, :update_manually)).to be_falsey
      end
    end
  end

  describe 'editor_button_json' do
    let(:tool) { @root_account.context_external_tools.new(name: "editor thing", domain: "www.example.com") }

    it 'includes a boolean false for use_tray' do
      tool.editor_button = { use_tray: "false" }
      json = ContextExternalTool.editor_button_json([tool], @course, user_with_pseudonym)
      expect(json[0][:use_tray]).to eq false
    end

    it 'includes a boolean true for use_tray' do
      tool.editor_button = { use_tray: "true" }
      json = ContextExternalTool.editor_button_json([tool], @course, user_with_pseudonym)
      expect(json[0][:use_tray]).to eq true
    end

    describe 'includes the description' do
      it 'parsed into HTML' do
        tool.editor_button = {}
        tool.description = "the first paragraph.\n\nthe second paragraph."
        json = ContextExternalTool.editor_button_json([tool], @course, user_with_pseudonym)
        expect(json[0][:description]).to eq "<p>the first paragraph.</p>\n\n<p>the second paragraph.</p>\n"
      end

      it 'with target="_blank" on links' do
        tool.editor_button = {}
        tool.description = "[link text](http://the.url)"
        json = ContextExternalTool.editor_button_json([tool], @course, user_with_pseudonym)
        expect(json[0][:description]).to eq "<p><a href=\"http://the.url\" target=\"_blank\">link text</a></p>\n"
      end
    end
  end

  describe 'is_rce_favorite' do
    def tool_in_context(context)
      ContextExternalTool.create!(
        context: context,
        consumer_key: 'key',
        shared_secret: 'secret',
        name: 'test tool',
        url: 'http://www.tool.com/launch',
        editor_button: { url: 'http://example.com', icon_url: 'http://example.com' }
      )
    end

    it 'can be an rce favorite if it has an editor_button placement' do
      tool = tool_in_context(@root_account)
      expect(tool.can_be_rce_favorite?).to eq true
    end

    it 'cannot be an rce favorite if no editor_button placement' do
      tool = tool_in_context(@root_account)
      tool.editor_button = nil
      tool.save!
      expect(tool.can_be_rce_favorite?).to eq false
    end

    it 'does not set tools as an rce favorite for any context by default' do
      sub_account = @root_account.sub_accounts.create!
      tool = tool_in_context(@root_account)
      expect(tool.is_rce_favorite_in_context?(@root_account)).to eq false
      expect(tool.is_rce_favorite_in_context?(sub_account)).to eq false
    end

    it 'inherits from the old is_rce_favorite column if the accounts have not be seen up yet' do
      sub_account = @root_account.sub_accounts.create!
      tool = tool_in_context(@root_account)
      tool.is_rce_favorite = true
      tool.save!
      expect(tool.is_rce_favorite_in_context?(@root_account)).to eq true
      expect(tool.is_rce_favorite_in_context?(sub_account)).to eq true
    end

    it 'inherits from root account configuration if not set on sub-account' do
      sub_account = @root_account.sub_accounts.create!
      tool = tool_in_context(@root_account)
      @root_account.settings[:rce_favorite_tool_ids] = { value: [tool.global_id] }
      @root_account.save!
      expect(tool.is_rce_favorite_in_context?(@root_account)).to eq true
      expect(tool.is_rce_favorite_in_context?(sub_account)).to eq true
    end

    it 'overrides with sub-account configuration if specified' do
      sub_account = @root_account.sub_accounts.create!
      tool = tool_in_context(@root_account)
      @root_account.settings[:rce_favorite_tool_ids] = { value: [tool.global_id] }
      @root_account.save!
      sub_account.settings[:rce_favorite_tool_ids] = { value: [] }
      sub_account.save!
      expect(tool.is_rce_favorite_in_context?(@root_account)).to eq true
      expect(tool.is_rce_favorite_in_context?(sub_account)).to eq false
    end

    it 'can set sub-account tools as favorites' do
      sub_account = @root_account.sub_accounts.create!
      tool = tool_in_context(sub_account)
      sub_account.settings[:rce_favorite_tool_ids] = { value: [tool.global_id] }
      sub_account.save!
      expect(tool.is_rce_favorite_in_context?(sub_account)).to eq true
    end
  end

  describe 'upgrading from 1.1 to 1.3' do
    let(:old_tool) { external_tool_model(opts: { url: "https://special.url" }) }
    let(:tool) do
      t = old_tool.dup
      t.use_1_3 = true
      t.save!
      t
    end

    context 'prechecks' do
      it 'ignores 1.1 tools' do
        expect(old_tool).not_to receive(:prepare_for_ags)
        old_tool.prepare_for_ags_if_needed!
      end

      it 'ignores 1.3 tools without matching 1.1 tool' do
        other_tool = external_tool_model(opts: { url: "http://other.url" })
        expect(other_tool).not_to receive(:prepare_for_ags)
        other_tool.prepare_for_ags_if_needed!
      end

      it 'starts process when needed' do
        expect(tool).to receive(:prepare_for_ags)
        tool.prepare_for_ags_if_needed!
      end
    end

    context '#related_assignments' do
      let(:course) { course_model(account: account) }
      let(:account) { account_model }

      shared_examples_for 'finds related assignments' do
        before do
          # assignments that should never get returned
          diff_context = assignment_model(context: course_model)
          ContentTag.create!(context: diff_context, content: old_tool)
          diff_account = assignment_model(context: course_model(account: account_model))
          ContentTag.create!(context: diff_account, content: old_tool)
          invalid_url = assignment_model(context: course)
          ContentTag.create!(context: invalid_url, url: "https://invalid.url")
          other_tool = external_tool_model(opts: { url: "https://different.url" })
          diff_url = assignment_model(context: course)
          ContentTag.create!(context: diff_url, url: other_tool.url)
        end

        it 'finds assignments using tool id' do
          direct = assignment_model(context: course, title: "direct")
          ContentTag.create!(context: direct, content: old_tool)
          expect(tool.related_assignments(old_tool.id)).to eq([direct])
        end

        it 'finds assignments using tool url' do
          indirect = assignment_model(context: course, title: "indirect")
          ContentTag.create!(context: indirect, url: old_tool.url)
          expect(tool.related_assignments(old_tool.id)).to eq([indirect])
        end
      end

      context 'when installed in a course' do
        let(:old_tool) { external_tool_model(context: course, opts: { url: "https://special.url" }) }
        let(:tool) do
          t = old_tool.dup
          t.use_1_3 = true
          t.save!
          t
        end

        it_behaves_like 'finds related assignments'
      end

      context 'when installed in an account' do
        let(:old_tool) { external_tool_model(context: account, opts: { url: "https://special.url" }) }
        let(:tool) do
          t = old_tool.dup
          t.use_1_3 = true
          t.save!
          t
        end

        it_behaves_like 'finds related assignments'
      end
    end
  end
end
