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

# Assocates a rubric with an "association", or idea.  An assignment, for example.
# RubricAssessments, then, are concrete assessments of the artifacts associated
# with this idea, such as assignment submissions.
# The other purpose of this class is just to make rubrics reusable.
class RubricAssociation < ActiveRecord::Base
  include Canvas::SoftDeletable

  attr_accessor :skip_updating_points_possible
  attr_writer :updating_user

  belongs_to :rubric
  belongs_to :association_object, polymorphic: [:account, :course, :assignment],
                                  foreign_type: :association_type, foreign_key: :association_id,
                                  polymorphic_prefix: :association

  belongs_to :context, polymorphic: [:course, :account]
  has_many :rubric_assessments
  has_many :assessment_requests

  has_a_broadcast_policy

  validates_presence_of :purpose, :rubric_id, :association_id, :association_type, :context_id, :context_type
  validates :workflow_state, inclusion: { in: ["active", "deleted"] }

  before_create :set_root_account_id
  before_save :update_assignment_points
  before_save :update_values
  after_create :update_rubric
  after_create :link_to_assessments
  before_save :update_old_rubric
  after_destroy :update_rubric
  after_destroy :update_alignments
  after_save :assert_uniqueness
  after_save :update_alignments

  before_create :touch_association
  before_update :touch_association, :if => :will_save_change_to_rubric_id? # apparently we change the rubric sometimes
  before_destroy :touch_association
  serialize :summary_data

  with_options if: -> { auditable? && @updating_user.present? } do
    before_save :record_save_audit_event
    before_destroy :record_deletion_audit_event
  end

  ValidAssociationModels = {
    'Course' => ::Course,
    'Assignment' => ::Assignment,
    'Account' => ::Account,
  }

  # takes params[:association_type] and params[:association_id] and finds the
  # valid association object, if possible. Valid types are listed in
  # ValidAssociationModels. This doesn't verify the user has access to the
  # object.
  def self.get_association_object(params)
    return nil unless params

    a_type = params.delete(:association_type)
    a_id = params.delete(:association_id)
    return @context if a_type == @context.class.to_s && a_id == @context.id

    klass = ValidAssociationModels[a_type]
    return nil unless klass

    klass.where(id: a_id).first if a_id.present? # authorization is checked in the calling method
  end

  def restore
    self.workflow_state = "active"
    save
  end

  def course_broadcast_data
    context.broadcast_data if context.is_a?(Course)
  end

  set_broadcast_policy do |p|
    p.dispatch :rubric_association_created
    p.to { self.context.students rescue [] }
    p.whenever { |record|
      record.just_created && !record.context.is_a?(Course)
    }
    p.data { course_broadcast_data }
  end

  scope :active, -> { where("rubric_associations.workflow_state<>'deleted'") }
  scope :bookmarked, -> { where(:bookmarked => true) }
  scope :for_purpose, lambda { |purpose| where(:purpose => purpose) }
  scope :for_grading, -> { where(:purpose => 'grading') }
  scope :for_context_codes, lambda { |codes| where(:context_code => codes) }
  scope :include_rubric, -> { preload(:rubric) }
  scope :before, lambda { |date| where("rubric_associations.created_at<?", date) }

  def assert_uniqueness
    if purpose == 'grading'
      RubricAssociation.where(association_id: association_id, association_type: association_type, purpose: 'grading').each do |ra|
        next if ra == self

        ra.rubric_assessments.update_all(rubric_association_id: nil)
        ra.assessment_requests.update_all(rubric_association_id: nil)
        LearningOutcomeResult.where(association_object: ra).destroy_all
        ra.destroy_permanently!
      end
    end
  end

  def assignment
    if self.association_object.is_a?(Assignment)
      self.association_object
    else
      nil
    end
  end

  def update_alignments
    return unless assignment

    outcome_ids = self.deleted? ? [] : rubric.learning_outcome_alignments.map(&:learning_outcome_id)
    LearningOutcome.update_alignments(assignment, context, outcome_ids)
    true
  end

  def touch_association
    if self.association_type == "Assignment"
      self.class.connection.after_transaction_commit do
        self.association_object.touch
      end
    end
  end

  def update_old_rubric
    if self.rubric_id_changed? && self.rubric_id_was && self.rubric_id_was != self.rubric_id
      rubric = Rubric.find(self.rubric_id_was)
      rubric.destroy if rubric.rubric_associations.count == 0 && rubric.rubric_assessments.count == 0
    end
  end

  def context_name
    @cached_context_name ||= self.shard.activate do
      Rails.cache.fetch(['short_name_lookup', self.context_code].cache_key) do
        self.context.short_name rescue ""
      end
    end
  end

  def update_values
    self.bookmarked = true if self.purpose == 'bookmark' || self.bookmarked.nil?
    self.context_code ||= "#{self.context_type.underscore}_#{self.context_id}" rescue nil
    self.title ||= (self.association_object.title rescue self.association_object.name) rescue nil
    self.workflow_state ||= "active"
  end
  protected :update_values

  def user_can_assess_for?(assessor: nil, assessee: nil)
    raise "assessor and assessee required" unless assessor && assessee

    self.context.grants_right?(assessor, :manage_grades) || self.assessment_requests.incomplete.for_assessee(assessee).pluck(:assessor_id).include?(assessor.id)
  end

  def user_did_assess_for?(assessor: nil, assessee: nil)
    raise "assessor and assessee required" unless assessor && assessee

    self.assessment_requests.complete.for_assessee(assessee).for_assessor(assessor).any?
  end

  set_policy do
    given { |user, session| self.context.grants_right?(user, session, :manage_rubrics) }
    can :update and can :delete and can :manage

    given { |user, session| self.context.grants_right?(user, session, :participate_as_student) }
    can :submit

    given { |user, session| self.context.grants_right?(user, session, :view_all_grades) }
    can :view_rubric_assessments
  end

  def update_assignment_points
    if self.use_for_grading && !self.skip_updating_points_possible && self.association_object && self.association_object.respond_to?(:points_possible=) && self.rubric && self.rubric.points_possible && self.association_object.points_possible != self.rubric.points_possible
      self.association_object.points_possible = self.rubric.points_possible
      self.association_object.save
    end
  end
  protected :update_assignment_points

  def remind_user(assessee)
    assessment_request = self.assessment_requests.where(user_id: assessee).first
    assessment_request ||= self.assessment_requests.build(:user => assessee)
    assessment_request.send_reminder! if assessment_request.assigned?
    assessment_request
  end

  def update_rubric
    cnt = self.rubric.rubric_associations.for_grading.length rescue 0
    if self.rubric
      self.rubric.with_versioning(false) do
        self.rubric.read_only = cnt > 1
        self.rubric.association_count = cnt
        self.rubric.save

        self.rubric.destroy if cnt == 0 && self.rubric.rubric_associations.count == 0 && !self.rubric.public
      end
    end
  end
  protected :update_rubric

  # Link the rubric association to any existing assessment_requests (i.e. peer-reviews) that haven't been completed and
  # aren't currently linked to a rubric association. This routine is needed when an assignment is completed and
  # submissions were already sent when peer-review links and a *then* a rubric is created.
  def link_to_assessments
    # Go up to the assignment and loop through all submissions.
    # Update each submission's assessment_requests with a link to this rubric association
    # but only if not already associated
    if self.association_id && self.association_type == 'Assignment'
      self.association_object.submissions.each do |sub|
        sub.assessment_requests.where(:rubric_association_id => nil).update_all(:rubric_association_id => id, :workflow_state => 'assigned')
      end
    end
  end
  protected :link_to_assessments

  def unsubmitted_users
    self.context.students - self.rubric_assessments.map(&:user) - self.assessment_requests.map(&:user)
  end

  def self.generate(current_user, rubric, context, params)
    raise "context required" unless context

    association_object = params.delete :association_object
    if (association_id = params.delete(:id)) && association_id.present?
      association = RubricAssociation.where(id: association_id).first
    end
    association = nil unless association && association.context == context && association.association_object == association_object
    raise "association required" unless association || association_object

    # Update/create the association -- this is what ties the rubric to an entity
    update_if_existing = params.delete(:update_if_existing)
    if params[:hide_points] == '1'
      params[:use_for_grading] = '0'
      params[:hide_score_total] = '0'
    end
    association ||= rubric.associate_with(
      association_object,
      context,
      current_user: current_user,
      use_for_grading: params[:use_for_grading] == "1",
      purpose: params[:purpose],
      update_if_existing: update_if_existing
    )
    association.rubric = rubric
    if association.rubric_id_changed? && association_object.is_a?(Assignment)
      association_object.mark_downstream_changes(["rubric"])
    end
    association.context = context
    association.skip_updating_points_possible = params.delete :skip_updating_points_possible
    association.update(params)
    association.association_object = association_object
    association
  end

  def assessments_unique_per_asset?(assessment_type)
    self.association_object.is_a?(Assignment) && self.purpose == "grading" && assessment_type == "grading"
  end

  def assessment_points(criterion, data)
    if criterion.learning_outcome_id && !self.context.feature_enabled?(:outcome_extra_credit)
      [criterion.points, data[:points].to_f].min
    else
      data[:points].to_f
    end
  end
  protected :assessment_points

  def assess(opts = {})
    # TODO: what if this is for a group assignment?  Seems like it should
    # give all students for the group assignment the same rubric assessment
    # results.
    association = self
    params = opts[:assessment]
    raise "User required for assessing" unless opts[:user]
    raise "Assessor required for assessing" unless opts[:assessor]
    raise "Artifact required for assessing" unless opts[:artifact]
    raise "Assessment type required for assessing" unless params[:assessment_type]

    if opts[:artifact].is_a?(Quizzes::QuizSubmission)
      opts[:artifact] = self.association_object.find_or_create_submission(opts[:artifact].user)
    end

    if self.association_object.is_a?(Assignment) && !self.association_object.grade_group_students_individually
      group, students_to_assess = self.association_object.group_students(opts[:artifact].student)
      if group
        provisional_grader = opts[:artifact].is_a?(ModeratedGrading::ProvisionalGrade) && opts[:assessor]
        artifacts_to_assess = students_to_assess.map do |student|
          self.association_object.find_asset_for_assessment(self, student, :provisional_grader => provisional_grader).first
        end
      else
        artifacts_to_assess = [opts[:artifact]]
      end
    else
      artifacts_to_assess = [opts[:artifact]]
    end

    ratings = []
    score = nil
    replace_ratings = false
    has_score = false
    self.rubric.criteria_object.each do |criterion|
      data = params["criterion_#{criterion.id}".to_sym]
      rating = {}
      if data
        replace_ratings = true
        has_score = (data[:points]).present?
        rating[:id] = data[:rating_id]
        rating[:points] = assessment_points(criterion, data) if has_score
        rating[:criterion_id] = criterion.id
        rating[:learning_outcome_id] = criterion.learning_outcome_id
        if criterion.ignore_for_scoring
          rating[:ignore_for_scoring] = true
        elsif has_score
          score ||= 0
          score += rating[:points]
        end
        rating[:description] = data[:description]
        rating[:comments_enabled] = true
        rating[:comments] = data[:comments]
        rating[:above_threshold] = rating[:points] > criterion.mastery_points if criterion.mastery_points && rating[:points]
        criterion.ratings.each_with_index do |r, index|
          next unless ((r.points.to_f - rating[:points].to_f).abs < Float::EPSILON) ||
                      (criterion.criterion_use_range && r.points.to_f > rating[:points].to_f && criterion.ratings[index + 1].try(:points).to_f < rating[:points].to_f)

          rating[:description] ||= r.description
          rating[:id] ||= r.id
        end
        save_comment = data[:save_comment] == '1' && params[:assessment_type] != 'peer_review'
        if rating[:comments] && !rating[:comments].empty? && save_comment
          self.summary_data ||= {}
          self.summary_data[:saved_comments] ||= {}
          self.summary_data[:saved_comments][criterion.id.to_s] ||= []
          self.summary_data[:saved_comments][criterion.id.to_s] << rating[:comments]
          # TODO i18n
          self.summary_data[:saved_comments][criterion.id.to_s] = self.summary_data[:saved_comments][criterion.id.to_s].select { |desc| desc && !desc.empty? && desc != "No Details" }.uniq.sort
          self.save
        end
        rating[:description] = t('no_details', "No details") if !rating[:description] || rating[:description].empty?
        ratings << rating
      end
    end
    assessment_to_return = nil
    artifacts_to_assess.each do |artifact|
      assessment = nil
      if assessments_unique_per_asset?(params[:assessment_type])
        # Unless it's for grading, in which case assessments are unique per artifact (the assessor can change, depending on if the teacher/TA updates it)
        assessment = association.rubric_assessments.where(artifact_id: artifact, artifact_type: artifact.class.to_s, assessment_type: params[:assessment_type]).first
        # Update the assessor in case it did change
        assessment&.assessor = opts[:assessor]
      else
        # Assessments are unique per artifact/assessor/assessment_type.
        assessment = association.rubric_assessments.where(artifact_id: artifact, artifact_type: artifact.class.to_s, assessor_id: opts[:assessor], assessment_type: params[:assessment_type]).first
      end
      assessment ||= association.rubric_assessments.build(:assessor => opts[:assessor], :artifact => artifact, :user => artifact.student, :rubric => self.rubric, :assessment_type => params[:assessment_type])
      assessment.score = score if replace_ratings
      assessment.data = ratings if replace_ratings

      assessment.set_graded_anonymously if opts[:graded_anonymously]
      assessment.hide_points = association.hide_points
      assessment.save
      if artifact.is_a?(ModeratedGrading::ProvisionalGrade)
        artifact.submission.touch
      end
      assessment_to_return = assessment if assessment.artifact == opts[:artifact]
    end
    assessment_to_return
  end

  def auditable?
    assignment&.auditable?
  end

  private

  def record_save_audit_event
    existing_association = assignment.active_rubric_association? ? assignment.rubric_association : nil
    event_type = existing_association.present? ? 'rubric_updated' : 'rubric_created'
    payload = if event_type == 'rubric_created'
                { id: rubric_id }
              else
                { id: [existing_association.rubric_id, rubric_id] }
              end

    AnonymousOrModerationEvent.create!(
      assignment: assignment,
      event_type: event_type,
      payload: payload,
      user: @updating_user
    )
  end

  def record_deletion_audit_event
    AnonymousOrModerationEvent.create!(
      assignment: assignment,
      event_type: 'rubric_deleted',
      payload: { id: rubric_id },
      user: @updating_user
    )
  end

  def set_root_account_id
    self.root_account_id ||=
      if context_type == 'Account' && context.root_account?
        self.context.id
      else
        self.context&.root_account_id
      end
  end
end
