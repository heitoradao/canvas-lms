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

require_relative '../helpers/assignments_common'
require_relative '../helpers/differentiated_assignments'

describe "interaction with differentiated quizzes" do
  include_context "in-process server selenium tests"
  include DifferentiatedAssignments
  include AssignmentsCommon

  context "Student" do
    before do
      course_with_student_logged_in
      da_setup
      @da_quiz = create_da_quiz
    end

    context "Quiz and Assignment Index" do
      it "does not show inaccessible quizzes" do
        create_section_override_for_assignment(@da_quiz.assignment, course_section: @section1)
        get "/courses/#{@course.id}/assignments"
        expect(f(".ig-empty-msg")).to include_text("No Assignment Groups found")
        get "/courses/#{@course.id}/quizzes/"
        expect(f(".ig-empty-msg")).to include_text("No quizzes available")
      end

      it "shows quizzes with an override" do
        create_section_override_for_assignment(@da_quiz.assignment)
        get "/courses/#{@course.id}/assignments"
        expect(f("#assignment_group_upcoming")).to include_text(@da_quiz.title)
        get "/courses/#{@course.id}/quizzes"
        expect(f("#assignment-quizzes")).to include_text(@da_quiz.title)
      end

      it "shows quizzes with a graded submission" do
        @teacher = User.create!
        @course.enroll_teacher(@teacher)
        @da_quiz.assignment.grade_student(@student, grade: 10, grader: @teacher)
        get "/courses/#{@course.id}/assignments"
        expect(f("#assignment_group_undated")).to include_text(@da_quiz.title)
        get "/courses/#{@course.id}/quizzes"
        expect(f("#assignment-quizzes")).to include_text(@da_quiz.title)
      end
    end

    context "Quiz Show and Submission page" do
      it "redirects back to quizzes index from inaccessible quizzes" do
        create_section_override_for_assignment(@da_quiz.assignment, course_section: @section1)
        get "/courses/#{@course.id}/quizzes/#{@da_quiz.id}"
        expect(f("#flash_message_holder")).to include_text("You do not have access to the requested quiz.")
        expect(driver.current_url).to match %r{/courses/\d+/quizzes}
      end

      it "shows the quiz page with an override" do
        create_section_override_for_assignment(@da_quiz.assignment)
        get "/courses/#{@course.id}/quizzes/#{@da_quiz.id}"
        expect(driver.current_url).to match %r{/courses/\d+/quizzes/#{@da_quiz.id}}
      end

      it "shows the quiz page with a graded submission" do
        @teacher = User.create!
        @course.enroll_teacher(@teacher)
        @da_quiz.assignment.grade_student(@student, grade: 10, grader: @teacher)
        get "/courses/#{@course.id}/quizzes/#{@da_quiz.id}"
        expect(driver.current_url).to match %r{/courses/\d+/quizzes/#{@da_quiz.id}}
      end

      it "shows previous submissions on inaccessible quizzes" do
        @teacher = User.create!
        @course.enroll_teacher(@teacher)
        create_section_override_for_assignment(@da_quiz)
        submit_quiz(@da_quiz)
        # destroy the override and automatically generated grade providing visibility to the current student
        AssignmentOverride.find(@da_quiz.assignment_overrides.first!.id).destroy
        create_section_override_for_assignment(@da_quiz, course_section: @section1)
        # assure we get the no longer counted banner on the quiz page
        get "/courses/#{@course.id}/quizzes/#{@da_quiz.id}"
        expect(f("#flash_message_holder")).to include_text("This quiz will no longer count towards your grade.")
        # assure we get the no longer counted banner on the quiz submission page
        get "/courses/#{@course.id}/quizzes/#{@da_quiz.id}/submissions/#{@da_quiz.quiz_submissions.first!.id}"
        expect(f("#flash_message_holder")).to include_text("This quiz will no longer count towards your grade.")
      end

      it "does not allow you the quiz to be taken if visibility has been revoked" do
        @teacher = User.create!
        @course.enroll_teacher(@teacher)
        create_section_override_for_assignment(@da_quiz)
        submit_quiz(@da_quiz)
        AssignmentOverride.find(@da_quiz.assignment_overrides.first!.id).destroy
        create_section_override_for_assignment(@da_quiz, course_section: @section1)
        get "/courses/#{@course.id}/quizzes/#{@da_quiz.id}"
        expect(f("#content")).not_to contain_css(".take_quiz_link")
      end
    end

    context "Student Grades page" do
      it "shows a quiz with an override" do
        create_section_override_for_assignment(@da_quiz.assignment)
        get "/courses/#{@course.id}/grades"
        expect(f("#assignments")).to include_text(@da_quiz.title)
      end

      it "shows a quiz with a grade" do
        @teacher = User.create!
        @course.enroll_teacher(@teacher)
        @da_quiz.assignment.grade_student(@student, grade: 10, grader: @teacher)
        get "/courses/#{@course.id}/grades"
        expect(f("#assignments")).to include_text(@da_quiz.title)
      end

      it "does not show an inaccessible quiz" do
        create_section_override_for_assignment(@da_quiz.assignment, course_section: @section1)
        get "/courses/#{@course.id}/grades"
        expect(f("#assignments")).not_to include_text(@da_quiz.title)
      end
    end
  end
  context "Observer with student" do
    before do
      observer_setup
      da_setup
      @da_quiz = create_da_quiz
    end

    context "Quiz and Assignment Index" do
      it "does not show inaccessible quizzes" do
        create_section_override_for_assignment(@da_quiz.assignment, course_section: @section1)
        get "/courses/#{@course.id}/assignments"
        expect(f(".ig-empty-msg")).to include_text("No Assignment Groups found")
        get "/courses/#{@course.id}/quizzes/"
        expect(f(".ig-empty-msg")).to include_text("No quizzes available")
      end

      it "shows quizzes with an override" do
        create_section_override_for_assignment(@da_quiz.assignment)
        get "/courses/#{@course.id}/assignments"
        expect(f("#assignment_group_upcoming")).to include_text(@da_quiz.title)
        get "/courses/#{@course.id}/quizzes"
        expect(f("#assignment-quizzes")).to include_text(@da_quiz.title)
      end

      it "shows quizzes with a graded submission" do
        @teacher = User.create!
        @course.enroll_teacher(@teacher)
        @da_quiz.assignment.grade_student(@student, grade: 10, grader: @teacher)
        get "/courses/#{@course.id}/assignments"
        expect(f("#assignment_group_undated")).to include_text(@da_quiz.title)
        get "/courses/#{@course.id}/quizzes"
        expect(f("#assignment-quizzes")).to include_text(@da_quiz.title)
      end
    end

    context "Quiz Show and Submission page" do
      it "redirects back to quizzes index from inaccessible quizzes" do
        create_section_override_for_assignment(@da_quiz.assignment, course_section: @section1)
        get "/courses/#{@course.id}/quizzes/#{@da_quiz.id}"
        expect(f("#flash_message_holder")).to include_text("You do not have access to the requested quiz.")
        expect(driver.current_url).to match %r{/courses/\d+/quizzes}
      end

      it "shows the quiz page with an override" do
        create_section_override_for_assignment(@da_quiz.assignment)
        get "/courses/#{@course.id}/quizzes/#{@da_quiz.id}"
        expect(driver.current_url).to match %r{/courses/\d+/quizzes/#{@da_quiz.id}}
      end

      it "shows the quiz page with a graded submission" do
        @teacher = User.create!
        @course.enroll_teacher(@teacher)
        @da_quiz.assignment.grade_student(@student, grade: 10, grader: @teacher)
        get "/courses/#{@course.id}/quizzes/#{@da_quiz.id}"
        expect(driver.current_url).to match %r{/courses/\d+/quizzes/#{@da_quiz.id}}
      end

      it "shows previous submissions on inaccessible quizzes" do
        @teacher = User.create!
        @course.enroll_teacher(@teacher)
        create_section_override_for_assignment(@da_quiz)
        submit_quiz(@da_quiz)
        # destroy the override and automatically generated grade providing visibility to the current student
        AssignmentOverride.find(@da_quiz.assignment_overrides.first!.id).destroy
        create_section_override_for_assignment(@da_quiz, course_section: @section1)
        # assure we get the no longer counted banner on the quiz page
        get "/courses/#{@course.id}/quizzes/#{@da_quiz.id}"
        expect(f("#flash_message_holder")).to include_text("You do not have access to the requested quiz.")
        # assure we get the no longer counted banner on the quiz submission page
        get "/courses/#{@course.id}/quizzes/#{@da_quiz.id}/submissions/#{@da_quiz.quiz_submissions.first!.id}"
        expect(f("#flash_message_holder")).to include_text("This quiz will no longer count towards your grade.")
      end
    end

    context "Student Grades page" do
      it "shows a quiz with an override" do
        create_section_override_for_assignment(@da_quiz.assignment)
        get "/courses/#{@course.id}/grades"
        expect(f("#assignments")).to include_text(@da_quiz.title)
      end

      it "shows a quiz with a graded submission" do
        @teacher = User.create!
        @course.enroll_teacher(@teacher)
        @da_quiz.assignment.grade_student(@student, grade: 10, grader: @teacher)
        get "/courses/#{@course.id}/grades"
        expect(f("#assignments")).to include_text(@da_quiz.title)
      end

      it "does not show an inaccessible quiz" do
        create_section_override_for_assignment(@da_quiz.assignment, course_section: @section1)
        get "/courses/#{@course.id}/grades"
        expect(f("#assignments")).not_to include_text(@da_quiz.title)
      end
    end
  end
end
