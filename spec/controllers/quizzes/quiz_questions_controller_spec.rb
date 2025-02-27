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

describe Quizzes::QuizQuestionsController do
  def course_quiz(active = false)
    @quiz = @course.quizzes.create
    @quiz.workflow_state = "available" if active
    @quiz.save!
    @quiz
  end

  def quiz_question
    @question = @quiz.quiz_questions.build
    @question.write_attribute(:question_data, { :answers => [
                                { :id => 123456, :answer_text => 'asdf', :weight => 100 },
                                { :id => 654321, :answer_text => 'jkl;', :weight => 0 }
                              ] })
    @question.save!
    @question
  end

  def quiz_group
    @quiz.quiz_groups.create
  end

  before :once do
    course_with_teacher(active_all: true)
    course_quiz
  end

  describe "POST 'create'" do
    it "requires authorization" do
      post 'create', params: { :course_id => @course.id, :quiz_id => @quiz, :question => {} }
      assert_unauthorized
    end

    it "creates a quiz question" do
      user_session(@teacher)
      post 'create', params: { :course_id => @course.id, :quiz_id => @quiz, :question => {
        :question_type => "multiple_choice_question",
        :answers => {
          '0' => {
            :answer_text => 'asdf',
            :weight => 100
          },
          '1' => {
            :answer_text => 'jkl;',
            :weight => 0
          }
        }
      } }
      expect(assigns[:question]).not_to be_nil
      expect(assigns[:question].question_data).not_to be_nil
      expect(assigns[:question].question_data[:answers].length).to eql(2)
      expect(assigns[:quiz]).to eql(@quiz)
    end

    it "preserves ids, if provided, on create" do
      user_session(@teacher)
      post 'create', params: { :course_id => @course.id, :quiz_id => @quiz, :question => {
        :question_type => "multiple_choice_question",
        :answers => [
          {
            :id => 123456,
            :answer_text => 'asdf',
            :weight => 100
          },
          {
            :id => 654321,
            :answer_text => 'jkl;',
            :weight => 0
          },
          {
            :id => 654321,
            :answer_text => 'qwer',
            :weight => 0
          }
        ]
      } }
      expect(assigns[:question]).not_to be_nil
      expect(assigns[:question].question_data).not_to be_nil
      data = assigns[:question].question_data[:answers]

      expect(data.length).to eql(3)
      expect(data[0][:id]).to eql(123456)
      expect(data[1][:id]).to eql(654321)
      expect(data[2][:id]).not_to eql(654321)
    end

    it 'bounces data thats too long' do
      long_data = "abcdefghijklmnopqrstuvwxyz"
      16.times do
        long_data = "#{long_data}abcdefghijklmnopqrstuvwxyz#{long_data}"
      end
      user_session(@teacher)
      post 'create', params: { course_id: @course.id, quiz_id: @quiz, question: {
        question_text: long_data
      } }, xhr: true
      expect(response.body).to match(/max length is 16384/)
    end

    it 'strips the origin from local URLs in answers' do
      Account.site_admin.enable_feature!(:strip_origin_from_quiz_answer_file_references)
      user_session(@teacher)
      post 'create', params: { :course_id => @course.id, :quiz_id => @quiz, :question => {
        :question_type => "multiple_choice_question",
        :answers => {
          '0' => {
            :answer_html => "<a href='https://test.host:80/courses/#{@course.id}/files/27'>home</a>",
            :comment_html => "<a href='https://test.host:80/courses/#{@course.id}/assignments'>home</a>",
          }
        }
      } }
      expect(assigns[:question].question_data[:answers][0][:html]).not_to match(/https:\/\/test.host/)
      expect(assigns[:question].question_data[:answers][0][:html]).to match(/href=['"]\/courses\/#{@course.id}\/files\/27/)
    end

    it 'strips the origin from local URLs in answers when they are provided as an array' do
      Account.site_admin.enable_feature!(:strip_origin_from_quiz_answer_file_references)
      user_session(@teacher)
      post 'create', params: { :course_id => @course.id, :quiz_id => @quiz, :question => {
        :question_type => "multiple_choice_question",
        :answers => [{
          :answer_html => "<a href='https://test.host:80/courses/#{@course.id}/files/27'>home</a>",
          :comment_html => "<a href='https://test.host:80/courses/#{@course.id}/assignments'>home</a>",
        }]
      } }
      expect(assigns[:question].question_data[:answers][0][:html]).not_to match(/https:\/\/test.host/)
      expect(assigns[:question].question_data[:answers][0][:html]).to match(/href=['"]\/courses\/#{@course.id}\/files\/27/)
    end
  end

  describe "PUT 'update'" do
    before(:once) { quiz_question }

    it "requires authorization" do
      put 'update', params: { :course_id => @course.id, :quiz_id => @quiz, :id => @question.id, :question => {} }
      assert_unauthorized
    end

    it "updates a quiz question" do
      user_session(@teacher)
      put 'update', params: { :course_id => @course.id, :quiz_id => @quiz, :id => @question.id, :question => {
        :question_type => "multiple_choice_question",
        :answers => {
          '0' => {
            :answer_text => 'asdf',
            :weight => 100
          },
          '1' => {
            :answer_text => 'jkl;',
            :weight => 0
          },
          '2' => {
            :answert_text => 'qwer',
            :weight => 0
          }
        }
      } }
      expect(assigns[:question]).not_to be_nil
      expect(assigns[:question].question_data).not_to be_nil
      expect(assigns[:question].question_data[:answers].length).to eql(3)
      expect(assigns[:quiz]).to eql(@quiz)
    end

    it "preserves ids, if provided, on update" do
      user_session(@teacher)
      put 'update', params: { :course_id => @course.id, :quiz_id => @quiz, :id => @question.id, :question => {
        :question_type => "multiple_choice_question",
        :answers => {
          '0' => {
            :id => 123456,
            :answer_text => 'asdf',
            :weight => 100
          },
          '1' => {
            :id => 654321,
            :answer_text => 'jkl;',
            :weight => 0
          },
          '2' => {
            :id => 654321,
            :answer_text => 'qwer',
            :weight => 0
          }
        }
      } }
      expect(assigns[:question]).not_to be_nil
      expect(assigns[:question].question_data).not_to be_nil
      data = assigns[:question].question_data[:answers]
      expect(data.length).to eql(3)
      expect(data[0][:id]).to eql(123456)
      expect(data[1][:id]).to eql(654321)
      expect(data[2][:id]).not_to eql(654321)
    end

    it 'bounces data thats too long' do
      long_data = "abcdefghijklmnopqrstuvwxyz"
      16.times do
        long_data = "#{long_data}abcdefghijklmnopqrstuvwxyz#{long_data}"
      end
      user_session(@teacher)
      put 'update', params: { course_id: @course.id, quiz_id: @quiz, id: @question.id, question: {
        question_text: long_data
      } }, xhr: true
      expect(response.body).to match(/max length is 16384/)
    end

    it "deletes non-html comments if needed" do
      bank = @course.assessment_question_banks.create!(:title => 'Test Bank')
      aq = bank.assessment_questions.create!(:question_data => {
                                               :question_type => 'essay_question', :correct_comments => 'stuff', :correct_comments_html => "stuff"
                                             })

      # add the first question directly onto the quiz, so it shouldn't get "randomly" selected from the group
      linked_question = @quiz.quiz_questions.build(:question_data => aq.question_data)
      linked_question.assessment_question_id = aq.id
      linked_question.save!

      user_session(@teacher)
      put 'update', params: { :course_id => @course.id, :quiz_id => @quiz, :id => linked_question.id, :question => { :correct_comments_html => "" } }
      expect(response).to be_successful

      linked_question.reload
      expect(linked_question.question_data['correct_comments_html']).to be_blank
      expect(linked_question.question_data['correct_comments']).to be_blank
    end

    it "leaves assessment question verifiers" do
      @attachment = attachment_with_context(@course)
      bank = @course.assessment_question_banks.create!(:title => 'Test Bank')
      aq = bank.assessment_questions.create!(:question_data => {
                                               :question_type => 'essay_question',
                                               :question_text => "File ref:<img src=\"/courses/#{@course.id}/files/#{@attachment.id}/download\">"
                                             })

      translated_text = aq.reload.question_data['question_text']
      expect(translated_text).to match %r{/assessment_questions/\d+/files/\d+}
      expect(translated_text).to match(/verifier=/)

      # add the first question directly onto the quiz, so it shouldn't get "randomly" selected from the group
      linked_question = @quiz.quiz_questions.build(:question_data => aq.question_data)
      linked_question.assessment_question_id = aq.id
      linked_question.save!

      user_session(@teacher)
      put 'update', params: { :course_id => @course.id, :quiz_id => @quiz, :id => linked_question.id,
                              :question => { :question_text => translated_text } }
      expect(response).to be_successful

      linked_question.reload
      expect(linked_question.question_data['question_text']).to eq translated_text # leave alone
    end
  end
end
