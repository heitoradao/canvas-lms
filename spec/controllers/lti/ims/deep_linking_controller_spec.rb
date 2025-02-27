# frozen_string_literal: true

#
# Copyright (C) 2018 - present Instructure, Inc.
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

require_relative './concerns/deep_linking_spec_helper'

module Lti
  module IMS
    RSpec.describe DeepLinkingController do
      include_context 'deep_linking_spec_helper'

      describe '#deep_linking_response' do
        subject { post :deep_linking_response, params: params }

        let(:params) { { JWT: deep_linking_jwt, account_id: account.id } }

        it { is_expected.to be_ok }

        it 'sets the JS ENV' do
          expect(controller).to receive(:js_env).with(
            content_items: content_items,
            message: message,
            log: log,
            error_message: error_message,
            error_log: error_log,
            lti_endpoint: Rails.application.routes.url_helpers.polymorphic_url(
              [:retrieve, account, :external_tools],
              host: 'test.host'
            ),
            reload_page: false
          )

          subject
        end

        context 'when the messages/logs passed in are not strings' do
          let(:message) { { html: 'some message' } }
          let(:error_message) { { html: 'some error message' } }
          let(:log) { { html: 'some log' } }
          let(:error_log) { { html: 'some error log' } }

          it 'turns them into strings before calling js_env to prevent HTML injection' do
            expect(controller).to receive(:js_env).with(hash_including(
                                                          message: '{"html"=>"some message"}',
                                                          log: '{"html"=>"some log"}',
                                                          error_message: '{"html"=>"some error message"}',
                                                          error_log: '{"html"=>"some error log"}'
                                                        ))
            subject
          end
        end

        context 'create resource links' do
          let(:launch_url) { 'http://tool.url/launch' }
          let(:content_items) do
            [
              { type: 'ltiResourceLink', url: launch_url, title: 'Item 1' },
              { type: 'link', url: 'http://too.url/sample', title: 'Item 2' }
            ]
          end
          let!(:tool) do
            tool = external_tool_model(
              context: account,
              opts: {
                url: 'http://tool.url/login',
                developer_key: developer_key
              }
            )
            tool.settings[:use_1_3] = true
            tool.save!
            tool
          end

          it 'create a resource link into the account context' do
            subject

            expect(account.lti_resource_links.size).to eq 1
            expect(account.lti_resource_links.first.current_external_tool(account)).to eq tool
            expect(account.lti_resource_links.first.context).to eq account
          end

          it 'add the lookup_uuid to the to the content item' do
            subject

            content_items = controller.content_items
            lti_resource_links = account.lti_resource_links

            expect(content_items.first['lookup_uuid']).to eq lti_resource_links.first.lookup_uuid
          end
        end

        shared_examples_for 'errors' do
          let(:response_message) { raise 'set in examples' }

          it { is_expected.to be_bad_request }

          it 'responds with an error' do
            subject
            expect(json_parse['errors'].to_s).to include response_message
          end
        end

        context 'when the jti is being reused' do
          let(:jti) { 'static value' }
          let(:nonce_key) { "nonce::#{jti}" }

          before { Lti::Security.check_and_store_nonce(nonce_key, iat, 30.seconds) }

          it { is_expected.to be_successful }
        end

        context 'when the aud is invalid' do
          let(:aud) { 'banana' }

          it_behaves_like 'errors' do
            let(:response_message) { "the 'aud' is invalid" }
          end
        end

        context 'when the jwt format is invalid' do
          let(:deep_linking_jwt) { 'banana' }

          it_behaves_like 'errors' do
            let(:response_message) { 'JWT format is invalid' }
          end
        end

        context 'when the jwt has the wrong alg' do
          let(:alg) { :HS256 }
          let(:private_jwk) { SecureRandom.uuid }

          it_behaves_like 'errors' do
            let(:response_message) { 'JWT has unexpected alg' }
          end
        end

        context 'when jwt verification fails' do
          let(:private_jwk) do
            new_key = DeveloperKey.new
            new_key.generate_rsa_keypair!
            JSON::JWK.new(new_key.private_jwk)
          end

          it_behaves_like 'errors' do
            let(:response_message) { 'JWT verification failure' }
          end
        end

        context 'when a url is used to get public key' do
          let(:rsa_key_pair) { CanvasSecurity::RSAKeyPair.new }
          let(:url) { "https://get.public.jwk" }
          let(:public_jwk_url_response) do
            {
              keys: [
                public_jwk
              ]
            }
          end
          let(:stubbed_response) { double(success?: true, parsed_response: public_jwk_url_response) }

          before do
            allow(HTTParty).to receive(:get).with(url).and_return(stubbed_response)
          end

          context 'when there is no public jwk' do
            before do
              developer_key.update!(public_jwk: nil, public_jwk_url: url)
            end

            it { is_expected.to be_successful }
          end

          context 'when there is a public jwk' do
            before do
              developer_key.update!(public_jwk_url: url)
            end

            it { is_expected.to be_successful }
          end

          context 'when an empty object is returned' do
            let(:public_jwk_url_response) { {} }
            let(:response_message) { 'JWT verification failure' }

            before do
              developer_key.update!(public_jwk_url: url)
            end

            it do
              subject
              expect(json_parse['errors'].to_s).to include response_message
            end
          end

          context 'when the url is not valid giving a 404' do
            let(:stubbed_response) { double(success?: false, parsed_response: public_jwk_url_response.to_json) }
            let(:response_message) { 'JWT verification failure' }
            let(:public_jwk_url_response) do
              {
                success?: false, code: '404'
              }
            end

            before do
              developer_key.update!(public_jwk_url: url)
            end

            it do
              subject
              expect(json_parse['errors'].to_s).to include response_message
            end
          end
        end

        context 'when the developer key is not found' do
          let(:iss) { developer_key.global_id + 100 }

          it_behaves_like 'errors' do
            let(:response_message) { 'Client not found' }
          end
        end

        context 'when the developer key binding is off' do
          before do
            developer_key.developer_key_account_bindings.first.update!(
              workflow_state: 'off'
            )
          end

          it_behaves_like 'errors' do
            let(:response_message) { 'Developer key inactive in context' }
          end
        end

        context 'when the developer key is not active' do
          before do
            developer_key.update!(
              workflow_state: 'deleted'
            )
          end

          it_behaves_like 'errors' do
            let(:response_message) { 'Developer key inactive' }
          end
        end

        context 'when the iat is in the future' do
          let(:iat) { 1.hour.from_now.to_i }

          it_behaves_like 'errors' do
            let(:response_message) { "the 'iat' must not be in the future" }
          end
        end

        context 'when the exp is past' do
          let(:exp) { 1.hour.ago.to_i }

          it_behaves_like 'errors' do
            let(:response_message) { 'the JWT has expired' }
          end
        end

        context 'when module item content items are received' do
          let(:course) { course_model }
          let(:developer_key) do
            key = DeveloperKey.create!(account: course.account)
            key.generate_rsa_keypair!
            key.developer_key_account_bindings.first.update!(
              workflow_state: 'on'
            )
            key.save!
            key
          end

          let(:context_external_tool) do
            ContextExternalTool.create!(
              context: course.account,
              url: 'http://tool.url/login',
              name: 'test tool',
              shared_secret: 'secret',
              consumer_key: 'key',
              developer_key: developer_key,
              settings: { use_1_3: true }
            )
          end
          let(:launch_url) { 'http://tool.url/launch' }

          before do
            course
            user_session(@user)
            context_external_tool
          end

          context 'when context_module_id param is included' do
            let(:context_module) { course.context_modules.create!(:name => 'Test Module') }
            let(:params) { super().merge({ course_id: course.id, context_module_id: context_module.id }) }

            context 'single item' do
              let(:content_items) do
                [{ type: 'ltiResourceLink', url: launch_url, title: 'Item 1', custom_params: { "a" => "b" } }]
              end

              it "doesn't create a resource link" do
                # The resource links for these are rather created when the module item is created
                expect { subject }.not_to change { course.lti_resource_links.count }
              end

              it "doesn't create a module item" do
                expect { subject }.not_to change { context_module.content_tags.count }
              end
            end

            context 'multiple items' do
              let(:content_items) do
                [
                  { type: 'ltiResourceLink', url: launch_url, title: 'Item 1' },
                  { type: 'ltiResourceLink', url: launch_url, title: 'Item 2', custom: { mycustom: '123' } },
                  { type: 'ltiResourceLink', url: launch_url, title: 'Item 3' }
                ]
              end

              it 'creates multiple module items' do
                expect(subject).to be_successful
                expect(context_module.content_tags.count).to eq(3)
              end

              it 'creates all resource links' do
                expect(course.lti_resource_links).to be_empty
                expect(subject).to be_successful
                expect(course.lti_resource_links.size).to eq 3
              end

              it "adds the resource link as the content tag's associated asset" do
                expect(subject).to be_successful

                content_tags = context_module.content_tags
                lti_resource_links = course.lti_resource_links

                expect(content_tags.first.associated_asset).to eq(lti_resource_links.first)
                expect(content_tags.second.associated_asset).to eq(lti_resource_links.second)
                expect(content_tags.last.associated_asset).to eq(lti_resource_links.last)
              end

              it 'adds custom params to the resource links' do
                expect(subject).to be_successful
                expect(course.lti_resource_links.second.custom).to eq('mycustom' => '123')
              end

              it 'does not pass launch dimensions' do
                expect(subject).to be_successful
                expect(context_module.content_tags[0][:link_settings]).to be(nil)
              end

              context 'when content items have iframe property' do
                let(:content_items) do
                  [
                    { type: 'ltiResourceLink', url: 'http://tool.url', iframe: { width: 642, height: 842 }, title: 'Item 1' },
                    { type: 'ltiResourceLink', url: 'http://tool.url', iframe: { width: 642, height: 842 }, title: 'Item 2' },
                    { type: 'ltiResourceLink', url: 'http://tool.url', iframe: { width: 642, height: 842 }, title: 'Item 3' }
                  ]
                end

                it 'passes launch dimensions as link_settings' do
                  expect(subject).to be_successful
                  expect(context_module.content_tags[0][:link_settings]['selection_width']).to be(642)
                  expect(context_module.content_tags[0][:link_settings]['selection_height']).to be(842)
                end
              end

              context 'when the user is not authorized' do
                before do
                  u = User.create
                  user_session u
                end

                it "returns 'unauthorized' (and doesn't render twice)" do
                  subject
                  expect(response).to have_http_status(:unauthorized)
                end
              end
            end
          end

          context 'when placement should create new module' do
            let(:params) { super().merge({ course_id: course.id, placement: 'module_index_menu' }) }

            context 'when feature flag is disabled' do
              it 'does not change anything' do
                expect { subject }.not_to change { course.context_modules.count }
                expect { subject }.not_to change { course.lti_resource_links.count }
                expect { subject }.not_to change { ContentTag.where(context: course).count }
              end
            end

            context 'when feature flag is enabled' do
              before :once do
                course.root_account.enable_feature!(:lti_deep_linking_module_index_menu)
              end

              it 'creates a new context module' do
                expect { subject }.to change { course.context_modules.count }.by 1
              end

              context 'single item' do
                let(:content_items) do
                  [{ type: 'ltiResourceLink', url: launch_url, title: 'Item 1' }]
                end

                it "creates a resource link" do
                  expect { subject }.to change { course.lti_resource_links.count }.by 1
                end

                it "creates a module item" do
                  expect { subject }.to change { ContentTag.where(context: course).count }.by 1
                end
              end

              context 'multiple items' do
                let(:content_items) do
                  [
                    { type: 'ltiResourceLink', url: launch_url, title: 'Item 1' },
                    { type: 'ltiResourceLink', url: launch_url, title: 'Item 2' },
                    { type: 'ltiResourceLink', url: launch_url, title: 'Item 3' }
                  ]
                end

                it 'creates one resource link per item' do
                  expect { subject }.to change { course.lti_resource_links.count }.by 3
                end

                it 'creates one module item per item' do
                  expect { subject }.to change { ContentTag.where(context: course).count }.by 3
                end
              end
            end
          end
        end

        context 'when content items that contain line items are received' do
          let(:course) { course_model(account: account) }
          let(:context_external_tool) {
            ContextExternalTool.create!(
              context: course.account,
              url: 'http://tool.url/login',
              name: 'test tool',
              shared_secret: 'secret',
              consumer_key: 'key',
              developer_key: developer_key,
              settings: { use_1_3: true }
            )
          }

          let(:params) { super().merge({ course_id: course.id, placement: 'course_assignments_menu' }) }
          let(:launch_url) { 'http://tool.url/launch' }
          let(:content_items) { [content_item] }
          let(:content_item) do
            { type: 'ltiResourceLink', url: launch_url, title: 'Item 1', lineItem: lineItem }
          end
          let(:lineItem) do
            { scoreMaximum: 10 }
          end

          before do
            course
            user_session(@user)
            context_external_tool
            course.root_account.enable_feature! :lti_deep_linking_line_items
          end

          shared_examples_for 'does nothing' do
            it 'does not create an assignment' do
              expect { subject }.not_to change { course.assignments.count }
            end
          end

          context 'when feature flag is disabled' do
            before do
              course.root_account.disable_feature! :lti_deep_linking_line_items
            end

            it_behaves_like 'does nothing'
          end

          context 'when context is an account' do
            let(:params) { super().except(:course_id).merge({ account_id: account.id }) }

            it_behaves_like 'does nothing'
          end

          context 'when placement is not allowed to create line items' do
            let(:params) { super().merge({ placement: 'assignment_selection' }) }

            it_behaves_like 'does nothing'
          end

          context 'when required parameter scoreMaximum is absent' do
            let(:lineItem) { { label: 'will not work' } }

            it_behaves_like 'does nothing'
            it 'sends error in content item response' do
              subject
              expect(assigns[:js_env][:content_items].first).to have_key(:errors)
            end
          end

          it 'creates an assignment from lineItem data' do
            expect { subject }.to change { course.assignments.count }.by 1
          end

          context 'when content item includes available dates' do
            let(:content_item) do
              super().merge({ available: { startDateTime: Time.zone.now.iso8601, endDateTime: Time.zone.now.iso8601 } })
            end

            it 'sets assignment unlock date to startDateTime' do
              subject
              expect(Assignment.last.unlock_at).to eq content_item.dig(:available, :startDateTime)
            end

            it 'sets assignment lock date to endDateTime' do
              subject
              expect(Assignment.last.lock_at).to eq content_item.dig(:available, :endDateTime)
            end
          end

          context 'when content item includes submission dates' do
            let(:content_item) do
              super().merge({ submission: { endDateTime: Time.zone.now.iso8601 } })
            end

            it 'sets assignment due date to endDateTime' do
              subject
              expect(Assignment.last.due_at).to eq content_item.dig(:submission, :endDateTime)
            end
          end

          context 'when content item includes title' do
            let(:content_item) do
              super().merge({ title: 'hello' })
            end

            it 'uses title for assignment title' do
              subject
              expect(Assignment.last.title).to eq content_items.first.dig(:title)
            end
          end

          context 'when line item includes label' do
            let(:lineItem) do
              super().merge({ label: 'hello' })
            end

            it 'uses label for assignment title' do
              subject
              expect(Assignment.last.title).to eq content_items.first.dig(:lineItem, :label)
            end
          end

          context 'when line item includes tag' do
            let(:lineItem) do
              super().merge({ tag: 'hello' })
            end

            it 'stores tag on line item' do
              subject
              expect(Lti::LineItem.last.tag).to eq content_items.first.dig(:lineItem, :tag)
            end
          end

          context 'when line item includes resourceId' do
            let(:lineItem) do
              super().merge({ resourceId: 'hello' })
            end

            it 'stores resourceId on line item' do
              subject
              expect(Lti::LineItem.last.resource_id).to eq content_items.first.dig(:lineItem, :resourceId)
            end
          end

          context 'when content item includes custom' do
            let(:content_item) do
              super().merge({ custom: { hello: '$User.id' } })
            end

            it 'stores custom on resource link' do
              subject
              expect(Lti::ResourceLink.last.custom).to eq content_items.first[:custom].with_indifferent_access
            end
          end
        end
      end
    end
  end
end
