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
class ContentTag < ActiveRecord::Base
  class LastLinkToOutcomeNotDestroyed < StandardError
  end

  TABLED_CONTENT_TYPES = ['Attachment', 'Assignment', 'WikiPage', 'Quizzes::Quiz', 'LearningOutcome', 'DiscussionTopic',
                          'Rubric', 'ContextExternalTool', 'LearningOutcomeGroup', 'AssessmentQuestionBank', 'LiveAssessments::Assessment', 'Lti::MessageHandler'].freeze
  TABLELESS_CONTENT_TYPES = ['ContextModuleSubHeader', 'ExternalUrl'].freeze
  CONTENT_TYPES = (TABLED_CONTENT_TYPES + TABLELESS_CONTENT_TYPES).freeze

  include Workflow
  include SearchTermHelper

  include MasterCourses::Restrictor
  restrict_columns :state, [:workflow_state]

  belongs_to :content, polymorphic: [], exhaustive: false
  validates_inclusion_of :content_type, :allow_nil => true, :in => CONTENT_TYPES
  belongs_to :context, polymorphic:
      [:course, :learning_outcome_group, :assignment, :account,
       { quiz: 'Quizzes::Quiz' }]
  belongs_to :associated_asset, polymorphic: [:learning_outcome_group, lti_resource_link: 'Lti::ResourceLink'],
                                polymorphic_prefix: true
  belongs_to :context_module
  belongs_to :learning_outcome
  # This allows doing a has_many_through relationship on ContentTags for linked LearningOutcomes. (see LearningOutcomeContext)
  belongs_to :learning_outcome_content, :class_name => 'LearningOutcome', :foreign_key => :content_id
  has_many :learning_outcome_results
  belongs_to :root_account, class_name: 'Account'

  after_create :clear_stream_items_if_module_is_unpublished

  # This allows bypassing loading context for validation if we have
  # context_id and context_type set, but still allows validating when
  # context is not yet saved.
  validates_presence_of :context, :unless => proc { |tag| tag.context_id && tag.context_type }
  validates_presence_of :workflow_state
  validates_length_of :comments, :maximum => maximum_text_length, :allow_nil => true, :allow_blank => true
  before_save :associate_external_tool
  before_save :default_values
  before_save :set_root_account
  after_save :update_could_be_locked
  after_save :touch_context_module_after_transaction
  after_save :touch_context_if_learning_outcome
  after_save :run_due_date_cacher_for_quizzes_next
  after_save :clear_discussion_stream_items
  after_save :send_items_to_stream
  after_save :clear_total_outcomes_cache
  after_create :update_outcome_contexts

  include CustomValidations
  validates_as_url :url

  validate :check_for_restricted_content_changes

  acts_as_list :scope => :context_module

  set_policy do
    given { |user, session| self.context && self.context.grants_right?(user, session, :manage_content) }
    can :delete
  end

  workflow do
    state :active do
      event :unpublish, :transitions_to => :unpublished
    end
    state :unpublished do
      event :publish, :transitions_to => :active
    end
    state :deleted
  end

  alias_method :published?, :active?

  scope :active, -> { where(:workflow_state => 'active') }
  scope :not_deleted, -> { where("content_tags.workflow_state<>'deleted'") }

  attr_accessor :skip_touch

  def touch_context_module
    return true if skip_touch.present? || self.context_module_id.nil?

    ContentTag.touch_context_modules([self.context_module_id])
  end

  def touch_context_module_after_transaction
    self.class.connection.after_transaction_commit {
      touch_context_module
    }
  end
  private :touch_context_module_after_transaction

  def self.touch_context_modules(ids = [])
    if ids.length == 1
      ContextModule.where(id: ids).not_recently_touched.update_all(updated_at: Time.now.utc)
    elsif ids.empty?
      # do nothing
    else
      ContextModule.where(id: ids).not_recently_touched.touch_all
    end
    true
  end

  def touch_context_if_learning_outcome
    if (self.tag_type == 'learning_outcome_association' || self.tag_type == 'learning_outcome') && skip_touch.blank?
      self.context_type.constantize.where(:id => self.context_id).update_all(:updated_at => Time.now.utc)
    end
  end

  def update_outcome_contexts
    return unless self.tag_type == 'learning_outcome_association'

    if self.context_type == 'Account' || self.context_type == 'Course'
      self.content.add_root_account_id_for_context!(self.context)
    end
  end

  def associate_external_tool
    return if content.present? || content_type != 'ContextExternalTool' || context.blank? || url.blank?

    content = ContextExternalTool.find_external_tool(url, context)
    self.content = content if content
  end

  def default_values
    self.title ||= self.content.title rescue nil
    self.title ||= self.content.name rescue nil
    self.title ||= self.content.display_name rescue nil
    self.title ||= t(:no_title, "No title")
    self.comments ||= ""
    self.comments = "" if self.comments == "Comments"
    self.context_code = "#{self.context_type.to_s.underscore}_#{self.context_id}"
  end
  protected :default_values

  def context_code
    read_attribute(:context_code) || "#{self.context_type.to_s.underscore}_#{self.context_id}" rescue nil
  end

  def context_name
    self.context.name rescue ""
  end

  def update_could_be_locked
    ContentTag.update_could_be_locked([self]) unless skip_touch.present?
    true
  end

  def self.update_could_be_locked(tags = [])
    content_ids = {}
    tags.each do |t|
      (content_ids[t.content_type] ||= []) << t.content_id if t.content_type && t.content_id
    end
    content_ids.each do |type, ids|
      klass = type.constantize
      next unless klass < ActiveRecord::Base
      next if klass < Tableless

      if klass.new.respond_to?(:could_be_locked=)
        klass.where(id: ids).update_all_locked_in_order(could_be_locked: true)
      end
    end
  end

  def confirm_valid_module_requirements
    self.context_module && self.context_module.confirm_valid_requirements
  end

  def scoreable?
    self.content_type_quiz? || self.graded?
  end

  def graded?
    return true if self.content_type == 'Assignment'
    return false if self.content_type == 'WikiPage'
    return false unless self.can_have_assignment?

    content && !content.assignment_id.nil?
  end

  def duplicate_able?
    case self.content_type_class
    when 'assignment'
      content&.can_duplicate?
    when 'discussion_topic', 'wiki_page'
      true
    else
      false
    end
  end

  def direct_shareable?
    content_id.to_i > 0 && direct_share_type
  end

  def direct_share_type
    ContentShare::CLASS_NAME_TO_TYPE[content_type]
  end

  def direct_share_select_class
    direct_share_type.pluralize
  end

  def content_type_class(is_student = false)
    case self.content_type
    when 'Assignment'
      if self.content && self.content.submission_types == 'online_quiz'
        is_student ? 'lti-quiz' : 'quiz'
      elsif self.content && self.content.submission_types == 'discussion_topic'
        'discussion_topic'
      elsif self&.content&.quiz_lti?
        'lti-quiz'
      else
        'assignment'
      end
    when 'Quizzes::Quiz'
      is_student ? 'lti-quiz' : 'quiz'
    else
      self.content_type.underscore
    end
  rescue
    (self.content_type || "").underscore
  end

  def item_class
    (self.content_type || "").gsub(/\A[A-Za-z]+::/, '') + '_' + self.content_id.to_s
  end

  def can_have_assignment?
    ['Assignment', 'DiscussionTopic', 'Quizzes::Quiz', 'WikiPage'].include?(self.content_type)
  end

  def assignment
    if self.content_type == 'Assignment'
      self.content
    elsif can_have_assignment?
      self.content&.assignment
    else
      nil
    end
  end

  alias_method :old_content, :content
  def content
    TABLELESS_CONTENT_TYPES.include?(self.content_type) ? nil : old_content
  end

  def content_or_self
    content || self
  end

  def asset_safe_title(column)
    name = self.title.to_s
    if (limit = self.content.class.try(:columns_hash)[column].try(:limit)) && name.length > limit
      name = name[0, limit][/.{0,#{limit}}/mu]
    end
    name
  end

  def self.asset_workflow_state(asset)
    if asset.respond_to?(:published?)
      if asset.respond_to?(:deleted?) && asset.deleted?
        'deleted'
      elsif asset.published?
        'active'
      else
        'unpublished'
      end
    else
      if asset.respond_to?(:workflow_state)
        workflow_state = asset.workflow_state.to_s
        if ['active', 'available', 'published'].include?(workflow_state)
          'active'
        elsif ['unpublished', 'deleted'].include?(workflow_state)
          workflow_state
        end
      else
        nil
      end
    end
  end

  def asset_workflow_state
    ContentTag.asset_workflow_state(self.content)
  end

  def asset_context_matches?
    self.content && self.content.respond_to?(:context) && self.content.context == context
  end

  def update_asset_name!(user = nil)
    return unless self.sync_title_to_asset_title?
    return unless self.asset_context_matches?

    # Assignment proxies name= and name to title= and title, which breaks the asset_safe_title logic
    if content.respond_to?("name=") && content.respond_to?("name") && !content.is_a?(Assignment)
      content.name = asset_safe_title('name')
    elsif content.respond_to?("title=")
      content.title = asset_safe_title('title')
    elsif content.respond_to?("display_name=")
      content.display_name = asset_safe_title('display_name')
    end
    if content.changed?
      content.user = user if user && content.is_a?(WikiPage)
      content.save
    end
  end

  def update_asset_workflow_state!
    return unless self.sync_workflow_state_to_asset?
    return unless self.asset_context_matches?
    return unless self.content && self.content.respond_to?(:publish!)

    # update the asset and also update _other_ content tags that point at it
    if self.unpublished? && self.content.published? && self.content.can_unpublish?
      self.content.unpublish!
      self.class.update_for(self.content, exclude_tag: self)
    elsif self.active? && !self.content.published?
      self.content.publish!
      self.class.update_for(self.content, exclude_tag: self)
    end
  end

  def self.delete_for(asset)
    ContentTag.where(content_id: asset, content_type: asset.class.to_s).each(&:destroy)
    ContentTag.where(context_id: asset, context_type: asset.class.to_s).each(&:destroy)
  end

  def can_destroy?
    # if it's a learning outcome link...
    if self.tag_type == 'learning_outcome_association'
      # and there are no other links to the same outcome in the same context...
      outcome = self.content
      other_link = ContentTag.learning_outcome_links.active
                             .where(:context_type => self.context_type, :context_id => self.context_id, :content_id => outcome)
                             .where("id<>?", self).first
      unless other_link
        # and there are alignments to the outcome (in the link's context for
        # foreign links, in any context for native links)
        alignment_conditions = { :learning_outcome_id => outcome.id }
        native = outcome.context_type == self.context_type && outcome.context_id == self.context_id
        if native
          @should_destroy_outcome = true
        else
          alignment_conditions[:context_id] = self.context_id
          alignment_conditions[:context_type] = self.context_type
        end

        @active_alignment_tags = ContentTag.learning_outcome_alignments.active.where(alignment_conditions)
        if @active_alignment_tags.exists?
          # then don't let them delete the link
          return false
        end
      end
    end
    true
  end

  alias_method :destroy_permanently!, :destroy
  def destroy
    unless can_destroy?
      aligned_outcome = @active_alignment_tags.map(&:learning_outcome).first.short_description
      raise LastLinkToOutcomeNotDestroyed.new "Outcome '#{aligned_outcome}' cannot be deleted because it is aligned to content."
    end

    context_module.remove_completion_requirement(id) if context_module

    self.workflow_state = 'deleted'
    self.save!

    # for outcome links delete the associated friendly description
    delete_outcome_friendly_description if self.content_type == 'LearningOutcome'

    run_due_date_cacher_for_quizzes_next(force: true)

    # after deleting the last native link to an unaligned outcome, delete the
    # outcome. we do this here instead of in LearningOutcome#destroy because
    # (a) LearningOutcome#destroy *should* only ever be called from here, and
    # (b) we've already determined other_link and native
    if @should_destroy_outcome
      self.content.destroy
    end

    true
  end

  def locked_for?(user, opts = {})
    return unless self.context_module && !self.context_module.deleted?

    self.context_module.locked_for?(user, opts.merge({ :tag => self }))
  end

  def available_for?(user, opts = {})
    self.context_module.available_for?(user, opts.merge({ :tag => self }))
  end

  def send_items_to_stream
    if self.content_type == "DiscussionTopic" && self.saved_change_to_workflow_state? && self.workflow_state == 'active'
      content.send_items_to_stream
    end
  end

  def clear_discussion_stream_items
    if self.content_type == "DiscussionTopic"
      if self.saved_change_to_workflow_state? &&
         ['active', nil].include?(self.workflow_state_before_last_save) &&
         self.workflow_state == 'unpublished'
        content.clear_stream_items
      end
    end
  end

  def clear_stream_items_if_module_is_unpublished
    if self.content_type == "DiscussionTopic" && context_module&.workflow_state == 'unpublished'
      content.clear_stream_items
    end
  end

  def self.update_for(asset, exclude_tag: nil)
    tags = ContentTag.where(:content_id => asset, :content_type => asset.class.to_s).not_deleted
    tags = tags.where('content_tags.id<>?', exclude_tag.id) if exclude_tag
    tags = tags.select([:id, :tag_type, :content_type, :context_module_id]).to_a
    return if tags.empty?

    module_ids = tags.map(&:context_module_id).compact

    # update title
    tag_ids = tags.select(&:sync_title_to_asset_title?).map(&:id)
    attr_hash = { :updated_at => Time.now.utc }
    { :display_name => :title, :name => :title, :title => :title }.each do |attr, val|
      attr_hash[val] = asset.send(attr) if asset.respond_to?(attr)
    end
    ContentTag.where(:id => tag_ids).update_all(attr_hash) unless tag_ids.empty?

    # update workflow_state
    tag_ids = tags.select(&:sync_workflow_state_to_asset?).map(&:id)
    attr_hash = { :updated_at => Time.now.utc }

    workflow_state = asset_workflow_state(asset)
    attr_hash[:workflow_state] = workflow_state if workflow_state
    ContentTag.where(:id => tag_ids).update_all(attr_hash) if attr_hash[:workflow_state] && !tag_ids.empty?

    # update the module timestamp
    ContentTag.touch_context_modules(module_ids)
  end

  def sync_title_to_asset_title?
    self.tag_type != "learning_outcome_association" && !['ContextExternalTool', 'Attachment'].member?(self.content_type)
  end

  def sync_workflow_state_to_asset?
    self.content_type_quiz? || ['Attachment', 'Assignment', 'WikiPage', 'DiscussionTopic'].include?(self.content_type)
  end

  def content_type_quiz?
    Quizzes::Quiz.class_names.include?(self.content_type)
  end

  def content_type_discussion?
    'DiscussionTopic' == self.content_type
  end

  def context_module_action(user, action, points = nil)
    GuardRail.activate(:primary) do
      self.context_module.update_for(user, action, self, points) if self.context_module
    end
  end

  def progression_for_user(user)
    context_module.context_module_progressions.where(user_id: user.id).first
  end

  def content_asset_string
    @content_asset_string ||= "#{self.content_type.underscore}_#{self.content_id}"
  end

  def associated_asset_string
    @associated_asset_string ||= "#{self.associated_asset_type.underscore}_#{self.associated_asset_id}"
  end

  def content_asset_string=(val)
    vals = val.split("_")
    id = vals.pop
    type = Context.asset_type_for_string(vals.join("_").classify)
    if type && id && id.to_i > 0
      self.content_type = type.to_s
      self.content_id = id
    end
  end

  def has_rubric_association?
    content.respond_to?(:rubric_association) && !!content.rubric_association&.active?
  end

  scope :for_tagged_url, lambda { |url, tag| where(:url => url, :tag => tag) }
  scope :for_context, lambda { |context|
    case context
    when Account
      where(context: context).union(for_associated_courses(context))
    else
      where(context: context)
    end
  }
  scope :for_associated_courses, lambda { |account|
    select("DISTINCT content_tags.*").joins("INNER JOIN
      #{CourseAccountAssociation.quoted_table_name} AS caa
      ON caa.course_id = content_tags.context_id AND content_tags.context_type = 'Course'
      AND caa.account_id = #{account.id}")
  }
  scope :learning_outcome_alignments, -> { where(:tag_type => 'learning_outcome') }
  scope :learning_outcome_links, -> { where(:tag_type => 'learning_outcome_association', :associated_asset_type => 'LearningOutcomeGroup', :content_type => 'LearningOutcome') }

  # Scopes For Differentiated Assignment Filtering:

  scope :visible_to_students_in_course_with_da, lambda { |user_ids, course_ids|
    differentiable_classes = ['Assignment', 'DiscussionTopic', 'Quiz', 'Quizzes::Quiz', 'WikiPage']
    scope = for_non_differentiable_classes(course_ids, differentiable_classes)

    cyoe_courses, non_cyoe_courses = Course.where(id: course_ids).partition { |course| ConditionalRelease::Service.enabled_in_context?(course) }
    if non_cyoe_courses.any?
      scope = scope.union(where(context_id: non_cyoe_courses, context_type: 'Course', content_type: 'WikiPage'))
    end
    if cyoe_courses.any?
      scope = scope.union(
        for_non_differentiable_wiki_pages(cyoe_courses.map(&:id)),
        for_differentiable_wiki_pages(user_ids, cyoe_courses.map(&:id))
      )
    end
    scope.union(
      for_non_differentiable_discussions(course_ids)
        .merge(DiscussionTopic.visible_to_student_sections(user_ids)),
      for_differentiable_assignments(user_ids, course_ids),
      for_differentiable_discussions(user_ids, course_ids)
        .merge(DiscussionTopic.visible_to_student_sections(user_ids)),
      for_differentiable_quizzes(user_ids, course_ids)
    )
  }

  scope :for_non_differentiable_classes, lambda { |course_ids, differentiable_classes|
    where(context_id: course_ids, context_type: 'Course').where.not(content_type: differentiable_classes)
  }

  scope :for_non_differentiable_discussions, lambda { |course_ids|
    joins("JOIN #{DiscussionTopic.quoted_table_name} as discussion_topics ON discussion_topics.id = content_tags.content_id")
      .where("content_tags.context_id IN (?)
             AND content_tags.context_type = 'Course'
             AND content_tags.content_type = 'DiscussionTopic'
             AND discussion_topics.assignment_id IS NULL", course_ids)
  }

  scope :for_non_differentiable_wiki_pages, lambda { |course_ids|
    joins("JOIN #{WikiPage.quoted_table_name} as wp ON wp.id = content_tags.content_id")
      .where("content_tags.context_id IN (?)
             AND content_tags.context_type = 'Course'
             AND content_tags.content_type = 'WikiPage'
             AND wp.assignment_id IS NULL", course_ids)
  }

  scope :for_differentiable_quizzes, lambda { |user_ids, course_ids|
    joins("JOIN #{Quizzes::QuizStudentVisibility.quoted_table_name} as qsv ON qsv.quiz_id = content_tags.content_id")
      .where("content_tags.context_id IN (?)
             AND content_tags.context_type = 'Course'
             AND qsv.course_id IN (?)
             AND content_tags.content_type in ('Quiz', 'Quizzes::Quiz')
             AND qsv.user_id = ANY( '{?}'::INT8[] )
        ", course_ids, course_ids, user_ids)
  }

  scope :for_differentiable_assignments, lambda { |user_ids, course_ids|
    joins("JOIN #{AssignmentStudentVisibility.quoted_table_name} as asv ON asv.assignment_id = content_tags.content_id")
      .where("content_tags.context_id IN (?)
             AND content_tags.context_type = 'Course'
             AND asv.course_id IN (?)
             AND content_tags.content_type = 'Assignment'
             AND asv.user_id = ANY( '{?}'::INT8[] )
        ", course_ids, course_ids, user_ids)
  }

  scope :for_differentiable_discussions, lambda { |user_ids, course_ids|
    joins("JOIN #{DiscussionTopic.quoted_table_name} ON discussion_topics.id = content_tags.content_id
           AND content_tags.content_type = 'DiscussionTopic'")
      .joins("JOIN #{AssignmentStudentVisibility.quoted_table_name} as asv ON asv.assignment_id = discussion_topics.assignment_id")
      .where("content_tags.context_id IN (?)
             AND content_tags.context_type = 'Course'
             AND asv.course_id IN (?)
             AND content_tags.content_type = 'DiscussionTopic'
             AND discussion_topics.assignment_id IS NOT NULL
             AND asv.user_id = ANY( '{?}'::INT8[] )
      ", course_ids, course_ids, user_ids)
  }

  scope :for_differentiable_wiki_pages, lambda { |user_ids, course_ids|
    joins("JOIN #{WikiPage.quoted_table_name} as wp on wp.id = content_tags.content_id
           AND content_tags.content_type = 'WikiPage'")
      .joins("JOIN #{AssignmentStudentVisibility.quoted_table_name} as asv on asv.assignment_id = wp.assignment_id")
      .where("content_tags.context_id IN (?)
             AND content_tags.context_type = 'Course'
             AND asv.course_id in (?)
             AND content_tags.content_type = 'WikiPage'
             AND wp.assignment_id IS NOT NULL
             AND asv.user_id = ANY( '{?}'::INT8[] )
      ", course_ids, course_ids, user_ids)
  }

  scope :can_have_assignment, -> { where(content_type: ['Assignment', 'DiscussionTopic', 'Quizzes::Quiz', 'WikiPage']) }

  # only intended for learning outcome links
  def self.outcome_title_order_by_clause
    best_unicode_collation_key("learning_outcomes.short_description")
  end

  def self.order_by_outcome_title
    eager_load(:learning_outcome_content).order(outcome_title_order_by_clause)
  end

  def visible_to_user?(user, opts = nil, session = nil)
    return unless self.context_module

    opts ||= self.context_module.visibility_for_user(user, session)
    return false unless opts[:can_read]

    return true if opts[:can_read_as_admin]
    return false unless self.published?

    if self.assignment
      self.assignment.visible_to_user?(user, opts)
    elsif self.content_type_quiz?
      self.content.visible_to_user?(user, opts)
    else
      true
    end
  end

  def mark_as_importing!(migration)
    @importing_migration = migration
  end

  def check_for_restricted_content_changes
    if !self.new_record? && self.title_changed? && !@importing_migration && self.content && self.content.respond_to?(:is_child_content?) &&
       self.content.is_child_content? && self.content.editing_restricted?(:content)
      self.errors.add(:title, "cannot change title - associated content locked by Master Course")
    end
  end

  def run_due_date_cacher_for_quizzes_next(force: false)
    # Quizzes next should ideally only ever be attached to an
    # assignment.  Let's ignore any other contexts.
    return unless context_type == "Assignment"

    DueDateCacher.recompute(context) if content.try(:quiz_lti?) && (force || workflow_state != 'deleted')
  end

  def set_root_account
    return if self.root_account_id.present?

    self.root_account_id = case self.context
                           when Account
                             self.context.resolved_root_account_id
                           else
                             self.context&.root_account_id
                           end
  end

  def quiz_lti
    @quiz_lti ||= has_attribute?(:content_type) && content_type == 'Assignment' ? content&.quiz_lti? : false
  end

  def to_json(options = {})
    super({ :methods => :quiz_lti }.merge(options))
  end

  def as_json(options = {})
    super({ :methods => :quiz_lti }.merge(options))
  end

  def clear_total_outcomes_cache
    return unless tag_type == 'learning_outcome_association' && associated_asset_type == 'LearningOutcomeGroup'

    clear_context = context_type == 'LearningOutcomeGroup' ? nil : context
    Outcomes::LearningOutcomeGroupChildren.new(clear_context).clear_total_outcomes_cache
  end

  def delete_outcome_friendly_description
    OutcomeFriendlyDescription.active.find_by(context: self.context, learning_outcome_id: self.content_id)&.destroy
  end
end
