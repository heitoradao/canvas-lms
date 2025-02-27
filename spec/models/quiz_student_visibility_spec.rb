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

describe "differentiated_assignments" do
  def course_with_differentiated_assignments_enabled
    @course = Course.create!
    @user = user_model
    @course.enroll_user(@user)
    @course.save!
  end

  def make_quiz(opts = {})
    @quiz = Quizzes::Quiz.create!({
                                    context: @course,
                                    description: 'descript foo',
                                    only_visible_to_overrides: opts[:ovto],
                                    points_possible: rand(1000),
                                    title: "I am a quiz"
                                  })
    @quiz.publish
    @quiz.save!
    @assignment = @quiz.assignment
  end

  def quiz_with_true_only_visible_to_overrides
    make_quiz({ date: nil, ovto: true })
  end

  def quiz_with_false_only_visible_to_overrides
    make_quiz({ date: Time.now, ovto: false })
  end

  def student_in_course_with_adhoc_override(quiz, opts = {})
    @user = opts[:user] || user_model
    StudentEnrollment.create!(:user => @user, :course => @course)
    ao = AssignmentOverride.new()
    ao.quiz = quiz
    ao.title = "ADHOC OVERRIDE"
    ao.workflow_state = "active"
    ao.set_type = "ADHOC"
    ao.save!
    override_student = ao.assignment_override_students.build
    override_student.user = @user
    override_student.save!
    quiz.reload
    @user
  end

  def enroller_user_in_section(section, opts = {})
    @user = opts[:user] || user_model
    StudentEnrollment.create!(:user => @user, :course => @course, :course_section => section)
  end

  def enroller_user_in_both_sections
    @user = user_model
    StudentEnrollment.create!(:user => @user, :course => @course, :course_section => @section_foo)
    StudentEnrollment.create!(:user => @user, :course => @course, :course_section => @section_bar)
  end

  def add_multiple_sections
    @default_section = @course.default_section
    @section_foo = @course.course_sections.create!(:name => 'foo')
    @section_bar = @course.course_sections.create!(:name => 'bar')
  end

  def create_override_for_quiz(quiz, &block)
    ao = AssignmentOverride.new()
    ao.quiz = quiz
    ao.title = "Lorem"
    ao.workflow_state = "active"
    block.call(ao)
    ao.save!
    quiz.reload
  end

  def give_section_foo_due_date(quiz)
    create_override_for_quiz(quiz) do |ao|
      ao.set = @section_foo
      ao.due_at = 3.weeks.from_now
    end
  end

  def ensure_user_does_not_see_quiz
    visible_quiz_ids = Quizzes::QuizStudentVisibility.where(user_id: @user.id, course_id: @course.id).pluck(:quiz_id)
    expect(visible_quiz_ids.map(&:to_i).include?(@quiz.id)).to be_falsey
    expect(Quizzes::QuizStudentVisibility.visible_quiz_ids_in_course_by_user(user_id: [@user.id], course_id: [@course.id])[@user.id]).not_to include(@quiz.id)
  end

  def ensure_user_sees_quiz
    visible_quiz_ids = Quizzes::QuizStudentVisibility.where(user_id: @user.id, course_id: @course.id).pluck(:quiz_id)
    expect(visible_quiz_ids.map(&:to_i).include?(@quiz.id)).to be_truthy
    expect(Quizzes::QuizStudentVisibility.visible_quiz_ids_in_course_by_user(user_id: [@user.id], course_id: [@course.id])[@user.id]).to include(@quiz.id)
  end

  context "table" do
    before do
      course_with_differentiated_assignments_enabled
      add_multiple_sections
      quiz_with_true_only_visible_to_overrides
      give_section_foo_due_date(@quiz)
      enroller_user_in_section(@section_foo)
      # at this point there should be an entry in the table
      @visibility_object = Quizzes::QuizStudentVisibility.first
    end

    it "returns objects" do
      expect(@visibility_object).not_to be_nil
    end

    it "doesnt allow updates" do
      @visibility_object.user_id = @visibility_object.user_id + 1
      expect { @visibility_object.save! }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "doesnt allow new records" do
      expect {
        Quizzes::QuizStudentVisibility.create!(user_id: @user.id,
                                               quiz_id: @quiz_id,
                                               course_id: @course.id)
      }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end

    it "doesnt allow deletion" do
      expect { @visibility_object.destroy }.to raise_error(ActiveRecord::ReadOnlyRecord)
    end
  end

  context "course_with_differentiated_assignments_enabled" do
    before do
      course_with_differentiated_assignments_enabled
      add_multiple_sections
    end

    context "quiz only visible to overrides" do
      before do
        quiz_with_true_only_visible_to_overrides
        give_section_foo_due_date(@quiz)
      end

      context "ADHOC overrides" do
        before { quiz_with_true_only_visible_to_overrides }

        it "returns a visibility for a student with an ADHOC override" do
          student_in_course_with_adhoc_override(@quiz)
          ensure_user_sees_quiz
        end

        it "works with course section and return a single visibility" do
          student_in_course_with_adhoc_override(@quiz)
          give_section_foo_due_date(@quiz)
          enroller_user_in_section(@section_foo)
          ensure_user_sees_quiz
          expect(Quizzes::QuizStudentVisibility.where(user_id: @user.id, course_id: @course.id, quiz_id: @quiz.id).count).to eq 1
        end

        it "does not return a visibility for a student without an ADHOC override" do
          @user = user_model
          ensure_user_does_not_see_quiz
        end

        it "does not return a visibility if ADHOC override is deleted" do
          student_in_course_with_adhoc_override(@quiz)
          @quiz.assignment_overrides.to_a.each(&:destroy)
          ensure_user_does_not_see_quiz
        end
      end

      context "user in section with override who then changes sections" do
        before do
          enroller_user_in_section(@section_foo)
          @student = @user
          teacher_in_course(course: @course)
        end

        it "does not keep the quiz visible even if there is a grade" do
          @quiz.assignment.grade_student(@student, grade: 10, grader: @teacher)
          Score.where(enrollment_id: @student.enrollments).each(&:destroy_permanently!)
          @student.enrollments.each(&:destroy_permanently!)
          enroller_user_in_section(@section_bar, { user: @student })
          ensure_user_does_not_see_quiz
        end

        it "does not keep the quiz visible if there is no score, even if it has a grade" do
          @quiz.assignment.grade_student(@student, grade: 10, grader: @teacher)
          @quiz.assignment.submissions.last.update_attribute("score", nil)
          @quiz.assignment.submissions.last.update_attribute("grade", 10)
          Score.where(enrollment_id: @student.enrollments).each(&:destroy_permanently!)
          @student.enrollments.each(&:destroy_permanently!)
          enroller_user_in_section(@section_bar, { user: @student })
          ensure_user_does_not_see_quiz
        end

        it "does not keep the quiz visible even if the grade is zero" do
          @quiz.assignment.grade_student(@student, grade: 0, grader: @teacher)
          Score.where(enrollment_id: @student.enrollments).each(&:destroy_permanently!)
          @student.enrollments.each(&:destroy_permanently!)
          enroller_user_in_section(@section_bar, { user: @student })
          ensure_user_does_not_see_quiz
        end
      end

      context "user in default section" do
        it "hides the quiz from the user" do
          ensure_user_does_not_see_quiz
        end
      end
      context "user in section with override" do
        before { enroller_user_in_section(@section_foo) }

        it "shows the quiz to the user" do
          ensure_user_sees_quiz
        end

        it "updates when enrollments change" do
          ensure_user_sees_quiz
          enrollments = StudentEnrollment.where(:user_id => @user.id, :course_id => @course.id, :course_section_id => @section_foo.id)
          Score.where(enrollment_id: enrollments).each(&:destroy_permanently!)
          enrollments.each(&:destroy_permanently!)
          ensure_user_does_not_see_quiz
        end

        it "updates when the override is deleted" do
          ensure_user_sees_quiz
          @quiz.assignment_overrides.to_a.each(&:destroy!)
          ensure_user_does_not_see_quiz
        end
      end
      context "user in section with no override" do
        before { enroller_user_in_section(@section_bar) }

        it "hides the quiz from the user" do
          ensure_user_does_not_see_quiz
        end
      end
      context "user in section with override and one without override" do
        before do
          enroller_user_in_both_sections
        end

        it "shows the quiz to the user" do
          ensure_user_sees_quiz
        end
      end
    end
    context "quiz with false only_visible_to_overrides" do
      before do
        quiz_with_false_only_visible_to_overrides
        give_section_foo_due_date(@quiz)
      end

      context "user in default section" do
        it "shows the quiz to the user" do
          ensure_user_sees_quiz
        end
      end
      context "user in section with override" do
        before { enroller_user_in_section(@section_foo) }

        it "shows the quiz to the user" do
          ensure_user_sees_quiz
        end
      end
      context "user in section with no override" do
        before { enroller_user_in_section(@section_bar) }

        it "shows the quiz to the user" do
          ensure_user_sees_quiz
        end
      end
      context "user in section with override and one without override" do
        before do
          enroller_user_in_both_sections
        end

        it "shows the quiz to the user" do
          ensure_user_sees_quiz
        end
      end
    end
  end
end
