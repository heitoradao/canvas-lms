# frozen_string_literal: true

#
# Copyright (C) 2012 - present Instructure, Inc.
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

class SortsAssignments
  VALID_BUCKETS = [:past, :overdue, :undated, :ungraded, :unsubmitted, :upcoming, :future]
  AssignmentsSortedByDueDate = Struct.new(*VALID_BUCKETS)

  class << self
    def by_due_date(opts)
      assignments = opts.fetch(:assignments)
      user = opts.fetch(:user)
      current_user = opts[:current_user] || opts.fetch(:user)
      session = opts.fetch(:session)
      submissions = opts[:submissions]
      upcoming_limit = opts[:upcoming_limit] || 1.week.from_now
      course = opts[:course]

      AssignmentsSortedByDueDate.new(
        -> { past(assignments) },
        -> { overdue(assignments, user, session, submissions) },
        -> { undated(assignments) },
        -> { ungraded_for_user_and_session(assignments, user, current_user, session) },
        -> { unsubmitted_for_user_and_session(course, assignments, user, current_user, session) },
        -> { upcoming(assignments, upcoming_limit) },
        -> { future(assignments) }
      )
    end

    def past(assignments)
      assignments ||= []
      dated(assignments).select { |assignment| assignment.due_at < Time.now }
    end

    def dated(assignments)
      assignments ||= []
      assignments.reject { |assignment| assignment.due_at == nil }
    end

    def undated(assignments)
      assignments ||= []
      assignments.select { |assignment| assignment.due_at == nil }
    end

    def unsubmitted_for_user_and_session(course, assignments, user, current_user, session)
      return [] unless course.grants_right?(current_user, session, :manage_grades)

      assignments ||= []
      assignments.select do |assignment|
        assignment.expects_submission? &&
          assignment.submission_for_student(user)[:id].blank?
      end
    end

    def upcoming(assignments, limit = 1.week.from_now)
      assignments ||= []
      dated(assignments).select { |a| due_between?(a, Time.now, limit) }
    end

    def future(assignments)
      assignments - past(assignments)
    end

    def up_to(assignments, time)
      dated(assignments).select { |assignment| assignment.due_at < time }
    end

    def down_to(assignments, time)
      dated(assignments).select { |assignment| assignment.due_at > time }
    end

    def ungraded_for_user_and_session(assignments, user, current_user, session)
      assignments ||= []
      assignments.select do |assignment|
        assignment.grants_right?(current_user, session, :grade) &&
          assignment.expects_submission? &&
          Assignments::NeedsGradingCountQuery.new(assignment, user).count > 0
      end
    end

    def without_graded_submission(assignments, submissions)
      assignments ||= []
      submissions ||= []
      submissions_by_assignment = submissions.inject({}) do |memo, sub|
        memo[sub.assignment_id] = sub
        memo
      end
      assignments.select do |assignment|
        match = submissions_by_assignment[assignment.id]
        !match || match.without_graded_submission?
      end
    end

    def user_allowed_to_submit(assignments, user, session)
      assignments ||= []
      assignments.select do |assignment|
        assignment.expects_submission? && assignment.grants_right?(user, session, :submit)
      end
    end

    def overdue(assignments, user, session, submissions)
      submissions ||= []
      assignments = past(assignments)
      user_allowed_to_submit(assignments, user, session) &
        without_graded_submission(assignments, submissions)
    end

    def bucket_filter(given_scope, bucket, session, user, current_user, context, submissions_for_user)
      overridden_assignments = given_scope.map { |a| a.overridden_for(user) }

      observed_students = ObserverEnrollment.observed_students(context, user)
      user_for_sorting = if observed_students.count == 1
                           observed_students.keys.first
                         else
                           user
                         end

      sorted_assignments = self.by_due_date(
        :course => context,
        :assignments => overridden_assignments,
        :user => user_for_sorting,
        :current_user => current_user,
        :session => session,
        :submissions => submissions_for_user
      )
      filtered_assignment_ids = sorted_assignments.send(bucket).call.map(&:id)
      given_scope.where(id: filtered_assignment_ids)
    end

    private

    def due_between?(assignment, start_time, end_time)
      assignment.due_at >= start_time && assignment.due_at <= end_time
    end
  end
end
