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

require 'apis/api_spec_helper'
require_relative './concerns/advantage_services_shared_context'
require_relative './concerns/advantage_services_shared_examples'
require_relative './concerns/lti_services_shared_examples'
require_dependency 'lti/ims/scores_controller'

module Lti::IMS
  RSpec.describe ScoresController do
    include_context 'advantage services context'

    let(:admin) { account_admin_user }
    let(:context) { course }
    let(:assignment) do
      opts = { course: course }
      if tool.present? && tool.use_1_3?
        opts[:submission_types] = 'external_tool'
        opts[:external_tool_tag_attributes] = {
          url: tool.url, content_type: 'context_external_tool', content_id: tool.id
        }
      end
      assignment_model(opts)
    end
    let(:unknown_context_id) { (Course.maximum(:id) || 0) + 1 }
    let(:line_item) do
      if assignment.external_tool? && tool.use_1_3?
        assignment.line_items.first
      else
        line_item_model(course: course)
      end
    end
    let(:user) { student_in_course(course: course, active_all: true).user }
    let(:line_item_id) { line_item.id }
    let(:result) do
      lti_result_model line_item: line_item, user: user, scoreGiven: nil, scoreMaximum: nil
    end
    let(:submission) { nil }
    let(:json) { JSON.parse(response.body) }
    let(:access_token_scopes) { 'https://purl.imsglobal.org/spec/lti-ags/scope/score' }
    let(:userId) { user.id }
    let(:params_overrides) do
      {
        course_id: context_id,
        line_item_id: line_item_id,
        userId: userId,
        activityProgress: 'Completed',
        gradingProgress: 'FullyGraded',
        timestamp: Time.zone.now.iso8601(3)
      }
    end
    let(:action) { :create }
    let(:scope_to_remove) { 'https://purl.imsglobal.org/spec/lti-ags/scope/score' }

    describe '#create' do
      let(:content_type) { 'application/vnd.ims.lis.v1.score+json' }

      it_behaves_like 'advantage services'
      it_behaves_like 'lti services'

      context 'with valid params' do
        context 'when the lti_id userId is used' do
          let(:userId) { user.lti_id }

          it 'returns a valid resultUrl in the body' do
            send_request
            expect(json['resultUrl']).to include 'results'
          end
        end

        it 'returns a valid resultUrl in the body' do
          send_request
          expect(json['resultUrl']).to include 'results'
        end

        context 'with no existing result' do
          it 'creates a new result' do
            expect { send_request }.to change(Lti::Result, :count).by(1)
          end

          it 'sets the updated_at and created_at to match the params timestamp' do
            send_request
            rslt = Lti::Result.find(json['resultUrl'].split('/').last)
            expect(rslt.created_at).to eq(params_overrides[:timestamp])
            expect(rslt.updated_at).to eq(params_overrides[:timestamp])
          end
        end

        context 'with existing result' do
          context do
            let(:params_overrides) do
              super().merge(scoreGiven: 5.0, scoreMaximum: line_item.score_maximum)
            end

            it 'updates result' do
              result
              expect { send_request }.to change(Lti::Result, :count).by(0)
              expect(result.reload.result_score).to eq 5.0
            end
          end

          it 'sets the updated_at to match the params timestamp' do
            send_request
            rslt = Lti::Result.find(json['resultUrl'].split('/').last)
            expect(rslt.updated_at).to eq(params_overrides[:timestamp])
          end

          context do
            let(:params_overrides) { super().merge(timestamp: 1.day.from_now) }

            it 'does not update the created_at timestamp' do
              result
              send_request
              rslt = Lti::Result.find(json['resultUrl'].split('/').last)
              expect(rslt.created_at).not_to eq(params_overrides[:timestamp])
            end
          end
        end

        context 'when line_item is not an assignment' do
          let(:line_item_no_submission) do
            line_item_model assignment: line_item.assignment,
                            resource_link: line_item.resource_link,
                            tool: tool
          end
          let(:line_item_id) { line_item_no_submission.id }

          context 'with gradingProgress set to FullyGraded or PendingManual' do
            let(:params_overrides) do
              super().merge(scoreGiven: 10, scoreMaximum: line_item.score_maximum)
            end

            it 'does not create submission' do
              send_request
              rslt = Lti::Result.find(json['resultUrl'].split('/').last)
              expect(rslt.submission).to be_nil
            end

            context do
              let(:params_overrides) { super().merge(gradingProgress: 'PendingManual') }

              it 'does not create submission with PendingManual' do
                send_request
                rslt = Lti::Result.find(json['resultUrl'].split('/').last)
                expect(rslt.submission).to be_nil
              end
            end
          end
        end

        context 'when line_item is an assignment' do
          let(:result) { lti_result_model line_item: line_item, user: user }

          shared_examples_for 'creates a new submission' do
            it 'increments attempt' do
              submission_body = { submitted_at: 1.hour.ago, submission_type: 'external_tool' }
              attempt = result.submission.assignment.submit_homework(user, submission_body).attempt
              send_request
              expect(result.submission.reload.attempt).to eq attempt + 1
            end
          end

          shared_examples_for 'updates existing submission' do
            it 'does not increment attempt or change submitted_at' do
              submission_body = { submitted_at: 1.hour.ago, submission_type: 'external_tool' }
              submission = result.submission.assignment.submit_homework(user, submission_body)
              attempt = submission.attempt
              submitted_at = submission.submitted_at
              send_request
              expect(result.submission.reload.attempt).to eq attempt
              expect(result.submission.reload.submitted_at).to eq submitted_at
            end
          end

          before { result }

          context 'default behavior' do
            it 'submits homework for module progression' do
              expect_any_instance_of(Assignment).to receive(:submit_homework)
              send_request
            end

            it 'uses submission_type of external_tool' do
              send_request
              expect(result.submission.reload.submission_type).to eq 'external_tool'
            end

            it_behaves_like 'creates a new submission'
          end

          context 'when "new_submission" extension is present and false' do
            let(:params_overrides) do
              super().merge(Lti::Result::AGS_EXT_SUBMISSION => { new_submission: false })
            end

            it 'does not submit homework' do
              expect_any_instance_of(Assignment).to_not receive(:submit_homework)
              expect_any_instance_of(Assignment).to receive(:find_or_create_submission)
              send_request
            end

            it_behaves_like 'updates existing submission'

            context 'when submitted_at is the same across submissions' do
              let(:params_overrides) do
                super().merge(
                  Lti::Result::AGS_EXT_SUBMISSION => {
                    new_submission: false, submitted_at: '2021-05-04T18:54:34.736+00:00'
                  }
                )
              end

              it 'does not decrement attempt' do
                # starting at attempt 0 doesn't work since it always goes back to 1 on save
                result.submission.update!(attempt: 4)
                attempt = result.submission.attempt
                send_request
                expect(result.submission.reload.attempt).to eq attempt
              end
            end
          end

          context 'when "new_submission" extension is present and true' do
            let(:params_overrides) do
              super().merge(Lti::Result::AGS_EXT_SUBMISSION => { new_submission: true })
            end

            it_behaves_like 'creates a new submission'
          end

          context 'when "submission_type" extension is none' do
            let(:params_overrides) do
              super().merge(Lti::Result::AGS_EXT_SUBMISSION => { submission_type: 'none' })
            end

            it 'does not submit homework' do
              expect_any_instance_of(Assignment).to_not receive(:submit_homework)
              expect_any_instance_of(Assignment).to receive(:find_or_create_submission)
              send_request
            end
          end

          context 'with no scoreGiven' do
            it 'does not update submission' do
              send_request
              expect(result.submission.reload.score).to be_nil
            end
          end

          context 'with gradingProgress not set to FullyGraded or PendingManual' do
            let(:params_overrides) { super().merge(scoreGiven: 100, gradingProgress: 'Pending') }

            it 'does not update submission' do
              send_request
              expect(result.submission.score).to be_nil
            end
          end

          context 'with gradingProgress set to FullyGraded or PendingManual' do
            let(:params_overrides) do
              super().merge(scoreGiven: 10, scoreMaximum: line_item.score_maximum)
            end

            it 'updates submission with FullyGraded' do
              send_request
              expect(result.submission.reload.score).to eq 10.0
            end

            context do
              let(:params_overrides) { super().merge(gradingProgress: 'PendingManual') }

              it 'updates submission with PendingManual' do
                send_request
                expect(result.submission.reload.score).to eq 10.0
              end
            end

            context 'with comment in payload' do
              let(:params_overrides) { super().merge(comment: 'Test coment') }

              it 'creates a new submission_comment' do
                send_request
                expect(result.submission.reload.submission_comments).not_to be_empty
              end
            end

            context 'with submission already graded' do
              let(:result) do
                lti_result_model line_item: line_item,
                                 user: user,
                                 result_score: 100,
                                 result_maximum: 10
              end

              it 'updates submission score' do
                expect(result.submission.score).to eq(100)
                send_request
                expect(result.submission.reload.score).to eq 10.0
              end
            end
          end

          context 'with submitted_at extension' do
            let(:params_overrides) do
              super().merge(Lti::Result::AGS_EXT_SUBMISSION => { submitted_at: submitted_at })
            end

            shared_examples_for 'updates submission time' do
              it do
                send_request
                expect(result.submission.reload.submitted_at).to eq submitted_at
              end
            end

            context 'when submitted_at is prior to submission due date' do
              let(:submitted_at) { 5.minutes.ago.iso8601(3) }

              before { result.submission.update!(cached_due_date: 2.minutes.ago.iso8601(3)) }

              it_behaves_like 'updates submission time'
              it_behaves_like 'creates a new submission'

              it 'does not mark submission late' do
                send_request
                expect(Submission.late.count).to eq 0
              end
            end

            context 'when submitted_at is after submission due date' do
              let(:submitted_at) { 2.minutes.ago.iso8601(3) }

              before { result.submission.update!(cached_due_date: 5.minutes.ago.iso8601(3)) }

              it_behaves_like 'updates submission time'
              it_behaves_like 'creates a new submission'

              it 'marks submission late' do
                send_request
                expect(Submission.late.count).to eq 1
              end
            end

            context 'when new_submission is present and false' do
              let(:submitted_at) { 5.minutes.ago.iso8601(3) }
              let(:params_overrides) do
                super().merge(
                  Lti::Result::AGS_EXT_SUBMISSION => {
                    submitted_at: submitted_at, new_submission: false
                  }
                )
              end

              it_behaves_like 'updates existing submission'
            end
          end

          context 'with content items in extension' do
            let(:content_items) do
              [
                {
                  type: 'file',
                  url: 'https://filesamples.com/samples/document/txt/sample1.txt',
                  title: 'sample1.txt'
                },
                {
                  type: 'not',
                  url: 'https://filesamples.com/samples/document/txt/sample1.txt',
                  title: 'notAFile.txt'
                }
              ]
            end
            let(:params_overrides) do
              super().merge(Lti::Result::AGS_EXT_SUBMISSION => { content_items: content_items, new_submission: false })
            end
            let(:expected_progress_url) do
              "http://test.host/api/lti/courses/#{context_id}/progress/"
            end

            it 'ignores content items that are not type file' do
              send_request
              expect(controller.send(:file_content_items)).to match_array [content_items.first]
            end

            it 'uses submission_type online_upload' do
              send_request
              expect(result.submission.reload.submission_type).to eq 'online_upload'
            end

            it 'only submits assignment once' do
              submission_body = { submitted_at: 1.hour.ago, submission_type: 'external_tool' }
              attempt = result.submission.assignment.submit_homework(user, submission_body).attempt
              send_request
              expect(result.submission.reload.attempt).to eq attempt + 1
            end

            context 'for assignment with attempt limit' do
              before { assignment.update!(allowed_attempts: 3) }

              context 'with an existing submission' do
                context 'when under attempt limit' do
                  it 'succeeds' do
                    send_request
                    expect(response.status.to_i).to eq 200
                  end
                end

                context 'when over attempt limit' do
                  it 'succeeds' do
                    result.submission.update!(attempt: 4)
                    send_request
                    expect(response.status.to_i).to eq 200
                  end
                end
              end

              context 'with a new submission' do
                let(:params_overrides) do
                  super().merge(Lti::Result::AGS_EXT_SUBMISSION => { content_items: content_items, new_submission: true })
                end

                context 'when under attempt limit' do
                  it 'succeeds' do
                    send_request
                    expect(response.status.to_i).to eq 200
                  end
                end

                context 'when over attempt limit' do
                  it 'fails' do
                    result.submission.update!(attempt: 4)
                    send_request
                    expect(response.status.to_i).to eq 422
                  end
                end
              end
            end

            shared_examples_for 'a file submission' do
              it 'creates an attachment' do
                send_request
                attachment = Attachment.last
                expect(attachment.user).to eq user
                expect(attachment.display_name).to eq content_items.first[:title]
                expect(result.submission.attachments).to include attachment
              end

              it 'returns a progress url' do
                send_request
                progress_url =
                  json[Lti::Result::AGS_EXT_SUBMISSION]['content_items'].first['progress']
                expect(progress_url).to include expected_progress_url
              end
            end

            context 'in local storage mode' do
              before do
                local_storage!
              end

              it_behaves_like 'creates a new submission'
              it_behaves_like 'a file submission'
            end

            context 'in s3 storage mode' do
              before do
                s3_storage!
              end

              it_behaves_like 'creates a new submission'
              it_behaves_like 'a file submission'
            end

            context 'with InstFS enabled' do
              before do
                allow(InstFS).to receive(:enabled?).and_return(true)
                allow(InstFS).to receive(:jwt_secrets).and_return(['jwt signing key'])
                @token = Canvas::Security.create_jwt({}, nil, InstFS.jwt_secret)
                allow(CanvasHttp).to receive(:post).and_return(
                  double(class: Net::HTTPCreated, code: 201, body: {})
                )
              end

              # it_behaves_like 'creates a new submission'
              # See spec/integration/scores_controller_spec.rb
              # for Instfs, we have to mock a request to the files capture API
              # that doesn't work well in a controller spec for this controller

              it 'returns a progress url' do
                send_request
                progress_url =
                  json[Lti::Result::AGS_EXT_SUBMISSION]['content_items'].first['progress']
                expect(progress_url).to include expected_progress_url
              end

              shared_examples_for 'a 400' do
                it 'returns bad request' do
                  send_request
                  expect(response).to be_bad_request
                end
              end

              shared_examples_for 'a 500' do
                it 'returns internal server error' do
                  send_request
                  expect(response).to be_server_error
                end
              end

              context 'when InstFS is unreachable' do
                before do
                  allow(CanvasHttp).to receive(:post).and_raise(Net::ReadTimeout)
                end

                it_behaves_like 'a 500'
              end

              context 'when InstFS responds with a 500' do
                before do
                  allow(CanvasHttp).to receive(:post).and_return(
                    double(class: Net::HTTPServerError, code: 500, body: {})
                  )
                end

                it_behaves_like 'a 500'
              end

              context 'when InstFS responds with a 400' do
                before do
                  allow(CanvasHttp).to receive(:post).and_return(
                    double(class: Net::HTTPBadRequest, code: 400, body: {})
                  )
                end

                it_behaves_like 'a 400'
              end
            end
          end
        end

        context 'when assignment has an attempt limit' do
          before { assignment.update!(allowed_attempts: 3) }

          let(:extension_overrides) { {} }

          shared_examples_for 'existing submission' do
            let(:params_overrides) do
              super().merge(
                Lti::Result::AGS_EXT_SUBMISSION => extension_overrides.merge({
                                                                               new_submission: false,
                                                                               submission_type: submission_type
                                                                             }),
                scoreGiven: 10,
                scoreMaximum: 10
              )
            end

            it 'succeeds when under limit' do
              send_request
              expect(response.status.to_i).to eq 200
            end

            it 'succeeds when over limit' do
              result.submission.update!(attempt: 4)
              send_request
              expect(response.status.to_i).to eq 200
            end
          end

          shared_examples_for 'attempt-limited new submission' do
            let(:params_overrides) do
              super().merge(
                Lti::Result::AGS_EXT_SUBMISSION => extension_overrides.merge({
                                                                               new_submission: true,
                                                                               submission_type: submission_type
                                                                             }),
                scoreGiven: 10,
                scoreMaximum: 10
              )
            end

            it 'succeeds when under limit' do
              send_request
              expect(response.status.to_i).to eq 200
            end

            it 'fails when over limit' do
              result.submission.update!(attempt: 4)
              send_request
              expect(response.status.to_i).to eq 422
            end
          end

          shared_examples_for 'attempt-unlimited new submission' do
            let(:params_overrides) do
              super().merge(
                Lti::Result::AGS_EXT_SUBMISSION => extension_overrides.merge({
                                                                               new_submission: true,
                                                                               submission_type: submission_type
                                                                             }),
                scoreGiven: 10,
                scoreMaximum: 10
              )
            end

            it 'succeeds when under limit' do
              send_request
              expect(response.status.to_i).to eq 200
            end

            it 'succeeds when over limit' do
              result.submission.update!(attempt: 4)
              send_request
              expect(response.status.to_i).to eq 200
            end
          end

          %w[online_url online_text_entry external_tool basic_lti_launch].each do |type|
            context "when submission_type is #{type}" do
              let(:submission_type) { type }

              it_behaves_like 'existing submission'
              it_behaves_like 'attempt-limited new submission'
            end
          end

          context "when submission_type is none" do
            let(:submission_type) { 'none' }

            it_behaves_like 'existing submission'

            context 'when new_submission is true' do
              let(:params_overrides) do
                super().merge(
                  Lti::Result::AGS_EXT_SUBMISSION => extension_overrides.merge({
                                                                                 new_submission: true,
                                                                                 submission_type: submission_type
                                                                               }),
                  scoreGiven: 10,
                  scoreMaximum: 10
                )
              end

              it 'succeeds when under limit' do
                send_request
                expect(response.status.to_i).to eq 200
              end

              it 'succeeds when over limit' do
                result.submission.update!(attempt: 4)
                send_request
                expect(response.status.to_i).to eq 200
              end
            end
          end
        end

        context 'with different scoreMaximum' do
          let(:params_overrides) { super().merge(scoreGiven: 10, scoreMaximum: 100) }

          it 'scales the submission but does not scale the score for the result' do
            result
            send_request
            expect(result.reload.result_score).to eq(params_overrides[:scoreGiven])
            expect(result.submission.reload.score).to eq(
              result.reload.result_score * (line_item.score_maximum / 100)
            )
          end
        end

        context 'with a ZERO score maximum' do
          let(:params_overrides) { super().merge(scoreGiven: 0, scoreMaximum: 0) }

          context "when the line item's maximum is zero" do
            it 'will tolerate a zero score' do
              line_item.update score_maximum: 0
              result
              send_request
              expect(response.status.to_i).to eq(200)
              expect(result.reload.result_score).to eq(0)
            end
          end

          context "when the line item's maximum is not zero" do
            it 'will not tolerate a zero score' do
              line_item.update score_maximum: 10
              result
              send_request
              expect(response.status.to_i).to eq(422)
              expect(response.body).to include("cannot be zero if line item's maximum is not zero")
            end
          end
        end

        context "with a NEGATIVE score maximum" do
          let(:params_overrides) { super().merge(scoreGiven: 0, scoreMaximum: -1) }

          it 'will not tolerate invalid score max' do
            result
            send_request
            expect(response.status.to_i).to eq(422)
          end
        end

        context 'with online_url' do
          let(:params_overrides) do
            super().merge(
              Lti::Result::AGS_EXT_SUBMISSION => {
                submission_type: 'online_url', submission_data: 'http://www.instructure.com'
              }
            )
          end

          it 'updates the submission and result url' do
            result
            send_request
            expect(
              result.reload.extensions[Lti::Result::AGS_EXT_SUBMISSION]['submission_type']
            ).to eq('online_url')
            expect(
              result.reload.extensions[Lti::Result::AGS_EXT_SUBMISSION]['submission_data']
            ).to eq('http://www.instructure.com')
            expect(result.submission.submission_type).to eq('online_url')
            expect(result.submission.url).to eq('http://www.instructure.com')
          end
        end

        context 'with basic_lti_launch' do
          let(:params_overrides) do
            super().merge(
              Lti::Result::AGS_EXT_SUBMISSION => {
                submission_type: 'basic_lti_launch',
                submission_data: 'http://www.instructure.com/launch_url'
              }
            )
          end

          it 'updates the submission and result url' do
            result
            send_request
            expect(
              result.reload.extensions[Lti::Result::AGS_EXT_SUBMISSION]['submission_type']
            ).to eq('basic_lti_launch')
            expect(
              result.reload.extensions[Lti::Result::AGS_EXT_SUBMISSION]['submission_data']
            ).to eq('http://www.instructure.com/launch_url')
            expect(result.submission.submission_type).to eq('basic_lti_launch')
            expect(result.submission.url).to eq('http://www.instructure.com/launch_url')
          end
        end

        context 'with online_text_entry' do
          let(:params_overrides) do
            super().merge(
              Lti::Result::AGS_EXT_SUBMISSION => {
                submission_type: 'online_text_entry', submission_data: '<p>Here is some text</p>'
              }
            )
          end

          it 'updates the submission and result body' do
            result
            send_request
            expect(
              result.reload.extensions[Lti::Result::AGS_EXT_SUBMISSION]['submission_type']
            ).to eq('online_text_entry')
            expect(
              result.reload.extensions[Lti::Result::AGS_EXT_SUBMISSION]['submission_data']
            ).to eq('<p>Here is some text</p>')
            expect(result.submission.submission_type).to eq('online_text_entry')
            expect(result.submission.body).to eq('<p>Here is some text</p>')
          end
        end

        context 'when previously graded and score not given' do
          let(:result) do
            lti_result_model line_item: line_item,
                             user: user,
                             result_score: 100,
                             result_maximum: 200
          end
          let(:params_overrides) { super().except(:scoreGiven, :scoreMaximum) }

          it 'clears the score' do
            expect(result.submission.score).to eq(100)
            expect(result.result_score).to eq(100)
            expect(result.result_maximum).to eq(200)
            send_request
            expect(result.reload.result_score).to be_nil
            expect(result.reload.result_maximum).to be_nil
            expect(result.submission.reload.score).to be_nil
          end
        end
      end

      context 'with invalid params' do
        shared_examples_for 'a bad request' do
          it 'does not process request' do
            result
            send_request
            expect(response).to be_bad_request
          end
        end

        shared_examples_for 'an unprocessable entity' do
          it 'returns an unprocessable_entity error' do
            result
            send_request
            expect(response).to have_http_status :unprocessable_entity
          end
        end

        context 'when timestamp is before updated_at' do
          let(:params_overrides) { super().merge(timestamp: 1.day.ago.iso8601(3)) }

          it_behaves_like 'a bad request'
        end

        context 'when scoreGiven is supplied without scoreMaximum' do
          let(:params_overrides) do
            super().merge(scoreGiven: 10, scoreMaximum: line_item.score_maximum).except(
              :scoreMaximum
            )
          end

          it_behaves_like 'an unprocessable entity'
        end

        context 'when model validation fails (score_maximum is not a number)' do
          let(:params_overrides) do
            super().merge(scoreGiven: 12.3456, scoreMaximum: 45.678)
          end

          before do
            allow_any_instance_of(Lti::Result).to receive(:update!).and_raise(
              ActiveRecord::RecordInvalid, Lti::Result.new.tap do |rf|
                rf.errors.add(:score_maximum, 'bogus error')
              end
            )
          end

          it_behaves_like 'an unprocessable entity'

          it 'does not update the submission' do
            expect {
              result
              send_request
            }.to_not change { result.submission.reload.score }
          end

          it 'has the model validation error in the response' do
            result
            send_request
            expect(response.body).to include('bogus error')
          end
        end

        context 'when user_id not found in course' do
          let(:user) { student_in_course(course: course_model, active_all: true).user }

          it_behaves_like 'an unprocessable entity'
        end

        context 'when user_id is not a student in course' do
          let(:user) { ta_in_course(course: course, active_all: true).user }

          it_behaves_like 'an unprocessable entity'
        end

        context 'when timestamp is not a string' do
          let(:params_overrides) { super().merge(timestamp: Time.zone.now.to_i) }

          it_behaves_like 'a bad request'
        end

        context 'when submitted_at extension is not a string' do
          let(:params_overrides) do
            super().merge(Lti::Result::AGS_EXT_SUBMISSION => { submitted_at: Time.zone.now.to_i })
          end

          it_behaves_like 'a bad request'
        end

        context 'when submitted_at extension is an invalid timestamp' do
          let(:params_overrides) do
            super().merge(Lti::Result::AGS_EXT_SUBMISSION => { submitted_at: 'asdf' })
          end

          it_behaves_like 'a bad request'
        end

        context 'when submitted_at is in the future' do
          let(:params_overrides) do
            super().merge(
              Lti::Result::AGS_EXT_SUBMISSION => { submitted_at: Time.zone.now + 5.minutes }
            )
          end

          it_behaves_like 'a bad request'
        end

        context 'when submission_type is online_upload but no content_items are included' do
          let(:params_overrides) do
            super().merge(
              Lti::Result::AGS_EXT_SUBMISSION => { submission_type: 'online_upload' }
            )
          end

          it_behaves_like 'an unprocessable entity'
        end
      end
    end
  end
end
