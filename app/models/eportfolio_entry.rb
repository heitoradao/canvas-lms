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

require 'atom'
require 'sanitize'

class EportfolioEntry < ActiveRecord::Base
  attr_readonly :eportfolio_id, :eportfolio_category_id
  belongs_to :eportfolio, touch: true
  belongs_to :eportfolio_category

  acts_as_list :scope => :eportfolio_category
  before_save :infer_unique_slug
  before_save :infer_comment_visibility
  after_save :check_for_spam, if: -> { eportfolio.needs_spam_review? }

  after_save :update_portfolio
  validates_presence_of :eportfolio_id
  validates_presence_of :eportfolio_category_id
  validates_length_of :name, :maximum => maximum_string_length, :allow_nil => false, :allow_blank => true
  validates_length_of :slug, :maximum => maximum_string_length, :allow_nil => false, :allow_blank => true
  has_many :page_comments, -> { preload(:user).order('page_comments.created_at DESC') }, as: :page

  serialize :content

  set_policy do
    given { |user| user && self.allow_comments }
    can :comment
  end

  def infer_comment_visibility
    self.show_comments = false unless self.allow_comments
    true
  end
  protected :infer_comment_visibility

  def update_portfolio
    self.eportfolio.save!
  end
  protected :update_portfolio

  def content_sections
    ((self.content.is_a?(String) && Array(self.content)) || self.content || []).map do |section|
      if section.is_a?(Hash)
        section.with_indifferent_access
      else
        section
      end
    end
  end

  def submission_ids
    res = []
    content_sections.each do |section|
      res << section["submission_id"] if section["section_type"] == "submission"
    end
    res
  end

  def full_slug
    (self.eportfolio_category.slug rescue "") + "_" + self.slug
  end

  def attachments
    res = []
    content_sections.each do |section|
      if section["attachment_id"].present? && section["section_type"] == "attachment"
        res << (self.eportfolio.user.all_attachments.where(id: section["attachment_id"]).first rescue nil)
      end
    end
    res.compact
  end

  def submissions
    res = []
    content_sections.each do |section|
      if section["submission_id"].present? && section["section_type"] == "submission"
        res << (self.eportfolio.user.submissions.where(id: section["submission_id"]).first rescue nil)
      end
    end
    res.compact
  end

  def parse_content(params)
    cnt = params[:section_count].to_i rescue 0
    self.content = []
    cnt.times do |idx|
      obj = params[("section_" + (idx + 1).to_s).to_sym].slice(:section_type, :content, :submission_id, :attachment_id)
      new_obj = { :section_type => obj[:section_type] }
      case obj[:section_type]
      when 'rich_text', 'html'
        config = CanvasSanitize::SANITIZE
        new_obj[:content] = Sanitize.clean(obj[:content] || '', config).strip
        new_obj = nil if new_obj[:content].empty?
      when 'submission'
        submission = eportfolio.user.submissions.where(id: obj[:submission_id]).exists? if obj[:submission_id].present?
        if submission
          new_obj[:submission_id] = obj[:submission_id].to_i
        else
          new_obj = nil
        end
      when 'attachment'
        attachment = eportfolio.user.attachments.active.where(id: obj[:attachment_id]).exists? if obj[:attachment_id].present?
        if attachment
          new_obj[:attachment_id] = obj[:attachment_id].to_i
        else
          new_obj = nil
        end
      else
        new_obj = nil
      end

      if new_obj
        self.content << new_obj
      end
    end
    self.content << t(:default_content, "No Content Added Yet") if self.content.empty?
  end

  def category_slug
    self.eportfolio_category.slug rescue self.eportfolio_category_id
  end

  def infer_unique_slug
    pages = self.eportfolio_category.eportfolio_entries rescue []
    self.name ||= t(:default_name, "Page Name")
    self.slug = self.name.gsub(/[\s]+/, "_").gsub(/[^\w\d]/, "")
    pages = pages.where("id<>?", self) unless self.new_record?
    match_cnt = pages.where(:slug => self.slug).count
    if match_cnt > 0
      self.slug = self.slug + "_" + (match_cnt + 1).to_s
    end
  end
  protected :infer_unique_slug

  def to_atom(opts = {})
    Atom::Entry.new do |entry|
      entry.title = self.name.to_s
      entry.authors << Atom::Person.new(:name => t(:atom_author, "ePortfolio Entry"))
      entry.updated   = self.updated_at
      entry.published = self.created_at
      url = "http://#{HostUrl.default_host}/eportfolios/#{self.eportfolio_id}/#{self.eportfolio_category.slug}/#{self.slug}"
      url += "?verifier=#{self.eportfolio.uuid}" if opts[:private]
      entry.links << Atom::Link.new(:rel => 'alternate', :href => url)
      entry.id = "tag:#{HostUrl.default_host},#{self.created_at.strftime("%Y-%m-%d")}:/eportfoli_entries/#{self.feed_code}_#{self.created_at.strftime("%Y-%m-%d-%H-%M") rescue "none"}"
      rendered_content = t(:click_through, "Click to view page content")
      entry.content = Atom::Content::Html.new(rendered_content)
    end
  end

  private

  def content_contains_spam?
    content_regexp = Eportfolio.spam_criteria_regexp(type: :content)
    return if content_regexp.blank?

    content_bodies = content_sections.map do |section|
      case section
      when String
        section
      when Hash
        section[:content]
      end
    end
    content_bodies.compact.any? { |content| content_regexp.match?(content) }
  end

  def check_for_spam
    eportfolio.flag_as_possible_spam! if eportfolio.title_contains_spam?(name) || content_contains_spam?
  end
end
