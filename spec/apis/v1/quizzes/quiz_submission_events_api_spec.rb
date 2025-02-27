# frozen_string_literal: true

#
# Copyright (C) 2014 - present Instructure, Inc.
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

require_relative '../../api_spec_helper'
require_relative '../../../models/quizzes/quiz_statistics/item_analysis/common'

describe Quizzes::QuizSubmissionEventsApiController, type: :request do
  require_relative '../../../quiz_spec_helper'

  describe 'POST /courses/:course_id/quizzes/:quiz_id/submissions/:id/events [create]' do
    def api_create(options = {}, data = {})
      url = "/api/v1/courses/#{@course.id}/quizzes/#{@quiz.id}/submissions/#{@quiz_submission.id}/events"
      params = { controller: 'quizzes/quiz_submission_events_api',
                 action: 'create',
                 format: 'json',
                 course_id: @course.id.to_s,
                 quiz_id: @quiz.id.to_s,
                 id: @quiz_submission.id.to_s }
      headers = { 'Accept' => 'application/vnd.api+json' }

      if options[:raw]
        raw_api_call(:post, url, params, data, headers)
      else
        api_call(:post, url, params, data, headers)
      end
    end

    events_data = [{
      "client_timestamp" => Time.zone.now.iso8601,
      "event_type" => "question_answered",
      "event_data" => { "question_id" => 1, "answer" => "1" }
    }, {
      "client_timestamp" => Time.zone.now.iso8601,
      "event_type" => "question_flagged",
      "event_data" => { "question_id" => 2, "flagged" => true }
    }]

    before :once do
      course_with_teacher :active_all => true

      simple_quiz_with_submissions %w{T T T}, %w{T T T}, %w{T F F}, %w{T F T},
                                   :user => @user,
                                   :course => @course

      @user = @teacher
    end

    it 'denies unauthorized access' do
      student_in_course
      @user = @teacher
      @quiz_submission = @quiz.quiz_submissions.last
      api_create({ raw: true }, {})
      assert_status(401)
    end

    it "responds with no_content success" do
      @quiz_submission = @quiz.quiz_submissions.last
      @user = User.find @quiz_submission.user_id
      expect(api_create({ raw: true }, { "quiz_submission_events" => events_data })).to eq 204
    end

    it 'stores the passed values into the DB table' do
      scope = Quizzes::QuizSubmissionEvent

      @quiz_submission = @quiz.quiz_submissions.last
      @user = User.find @quiz_submission.user_id

      expect(scope.where(event_type: ['question_answered', 'question_flagged']).count).to eq 0
      api_create({ raw: true }, { "quiz_submission_events" => events_data })
      expect(scope.where(event_type: ['question_answered', 'question_flagged']).count).to eq 2

      scope.where(event_type: 'question_answered').first.tap do |event|
        expect(event.event_type).to eq('question_answered')
        expect(event.event_data.as_json).to eq({
          question_id: '1',
          answer: '1'
        }.as_json)
      end
    end

    it "stores both client_timestamp and created_at" do
      scope = Quizzes::QuizSubmissionEvent

      @quiz_submission = @quiz.quiz_submissions.last
      @user = User.find @quiz_submission.user_id

      expect(scope.where(event_type: ['question_answered', 'question_flagged']).count).to eq 0
      api_create({ raw: true }, { "quiz_submission_events" => events_data })
      expect(scope.where(event_type: ['question_answered', 'question_flagged']).count).to eq 2

      scope.where(event_type: 'question_answered').first.tap do |event|
        expect(event.client_timestamp == events_data.first["client_timestamp"]).to be_truthy
        expect(event.created_at != events_data.first["client_timestamp"]).to be_truthy
        expect(event.created_at).to be_within(100).of(Time.zone.now)
      end
    end

    it 'does not succeed when the QS is `settings_only`' do
      student_in_course
      @quiz_submission = @quiz.quiz_submissions.create!(user: @user, workflow_state: 'settings_only')
      expect(api_create({ raw: true }, { 'quiz_submission_events' => events_data })).to eq 404
    end

    context 'for an ungraded quiz in a public course' do
      before do
        @course.is_public = true
        @course.is_public_to_auth_users = true
        @course.save!
        @quiz.quiz_type = 'practice_quiz'
        @quiz.save!
      end

      it 'responds with no_content success' do
        student_in_course
        @user = @teacher
        @quiz_submission = @quiz.quiz_submissions.last
        api_create({ raw: true }, {})
        assert_status(204)
      end
    end
  end

  describe 'GET /courses/:course_id/quizzes/:quiz_id/submissions/:id/events [index]' do
    def api_index(data = {})
      url = "/api/v1/courses/#{@course.id}/quizzes/#{@quiz.id}/submissions/#{@quiz_submission.id}/events"
      params = { controller: 'quizzes/quiz_submission_events_api',
                 action: 'index',
                 format: 'json',
                 course_id: @course.id.to_s,
                 quiz_id: @quiz.id.to_s,
                 id: @quiz_submission.id.to_s }
      headers = { 'Accept' => 'application/vnd.api+json' }

      if data.delete(:raw)
        raw_api_call(:get, url, params, data, headers)
      else
        api_call(:get, url, params, data, headers)
      end
    end

    before :once do
      Account.default.enable_feature!(:quiz_log_auditing)
      @quiz = course_factory(active_all: true).quizzes.create!
    end

    context 'as the student who took the quiz' do
      before :once do
        student_in_course(course: @course)
      end

      it 'does not let me in' do
        @quiz_submission = @quiz.generate_submission(@student)
        api_index({ raw: true })
        assert_status(401)
      end
    end

    context 'as the teacher' do
      before(:once) do
        teacher_in_course(course: @course)
        @quiz_submission = @quiz.generate_submission(@student)
      end

      it 'lets me in' do
        expect(api_index()).to have_key('quiz_submission_events')
      end

      context 'with a specific attempt' do
        before(:once) do
          student_in_course(course: @course)
          @quiz_submission = @quiz.generate_submission(@student)
          @quiz_submission.with_versioning(true, &:save!)

          @quiz_submission.attempt = 2
          @quiz_submission.with_versioning(true, &:save!)

          @quiz_submission.events.create!({ event_type: 'a', attempt: 1 })
          @quiz_submission.events.create!({ event_type: 'b', attempt: 2 })
          teacher_in_course(course: @course)
        end

        it 'works' do
          api_index({ attempt: 1 })['quiz_submission_events'].tap do |events|
            expect(events.count).to eq(2)
            expect(events[0]['event_type']).to eq('submission_created')
            expect(events[1]['event_type']).to eq('a')
          end

          api_index({ attempt: 2 })['quiz_submission_events'].tap do |events|
            expect(events.count).to eq(1)
            expect(events[0]['event_type']).to eq('b')
          end
        end
      end

      context 'with the latest attempt' do
        before(:once) do
          @quiz_submission = @quiz.generate_submission(@student)
          @quiz_submission.events.create!({
                                            event_type: 'something',
                                            event_data: ['test'],
                                            attempt: 1
                                          })
        end

        describe 'JSON-API compliance' do
          it 'conforms to the JSON-API spec when returning the object' do
            json = api_index
            assert_jsonapi_compliance(json, 'quiz_submission_events')
          end
        end
      end
    end

    context 'as someone else' do
      before(:once) do
        student_in_course(course: @course)
        user_factory(active_all: true)

        @quiz_submission = @quiz.generate_submission(@student)
      end

      it 'does not let me in' do
        api_index(raw: true)
        assert_status(401)
      end
    end
  end
end
