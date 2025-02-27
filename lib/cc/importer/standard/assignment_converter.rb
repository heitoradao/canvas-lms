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
module CC::Importer::Standard
  module AssignmentConverter
    include CC::Importer

    def convert_cc_assignments(asmnts = [])
      resources_by_type("assignment", "assignment_xmlv1p0").each do |res|
        if (doc = get_node_or_open_file(res, 'assignment'))
          path = res[:href] || (res[:files] && res[:files].first && res[:files].first[:href])
          resource_dir = File.dirname(path) if path

          asmnt = { :migration_id => res[:migration_id] }.with_indifferent_access
          if res[:intended_user_role] == 'Instructor'
            asmnt[:workflow_state] = 'unpublished'
          end
          parse_cc_assignment_data(asmnt, doc, resource_dir)

          # FIXME check the XML namespace to make sure it's actually a canvas assignment
          # (blocked by remove_namespaces! in lib/canvas/migration/migrator.rb)
          if (assgn_node = doc.at_css('extensions > assignment'))
            parse_canvas_assignment_data(assgn_node, nil, asmnt)
          end

          asmnts << asmnt
        end
      end

      asmnts
    end

    def parse_cc_assignment_data(asmnt, doc, resource_dir)
      asmnt[:description] = get_node_val(doc, 'text')
      asmnt[:description] = replace_urls(asmnt[:description]) unless @canvas_converter
      asmnt[:instructor_description] = get_node_val(doc, 'instructor_text')
      asmnt[:title] = get_node_val(doc, 'title')
      asmnt[:gradable] = get_bool_val(doc, 'gradable')
      if (points_possible = get_node_att(doc, 'gradable', 'points_possible'))
        asmnt[:grading_type] = 'points'
        asmnt[:points_possible] = points_possible.to_f
      end
      if doc.css('submission_formats format').length > 0
        asmnt[:submission_types] = []
        doc.css('submission_formats format').each do |format|
          type = format['type']
          type = 'online_text_entry' if type == 'text'
          type = 'online_text_entry' if type == 'html'
          type = 'online_url' if type == 'url'
          type = 'online_upload' if type == 'file'
          asmnt[:submission_types] << type
        end
        asmnt[:submission_types] = asmnt[:submission_types].uniq.join ','
      end

      if doc.css('attachment')
        asmnt[:description] += "\n<ul>"
        doc.css('attachment').each do |att_node|
          # todo next if type is teachers
          att_path = att_node['href']
          url = @canvas_converter ? att_path : (get_canvas_att_replacement_url(att_path, resource_dir) || att_path)
          asmnt[:description] += "\n<li><a href=\"#{url}\">#{File.basename att_path}</a>"
        end
        asmnt[:description] += "\n</ul>"
      end
    end

    def parse_canvas_assignment_data(meta_doc, html_doc = nil, assignment = {})
      if html_doc
        _title, body = get_html_title_and_body(html_doc)
        assignment['description'] = body
      end

      assignment["migration_id"] ||= get_node_att(meta_doc, 'assignment', 'identifier') || meta_doc['identifier']
      assignment["assignment_group_migration_id"] = get_node_val(meta_doc, "assignment_group_identifierref")
      assignment["grading_standard_migration_id"] = get_node_val(meta_doc, "grading_standard_identifierref")
      assignment["group_category"] = get_node_val(meta_doc, "group_category")
      assignment["grading_standard_id"] = get_node_val(meta_doc, "grading_standard_external_identifier")
      assignment["rubric_migration_id"] = get_node_val(meta_doc, "rubric_identifierref")
      assignment["rubric_id"] = get_node_val(meta_doc, "rubric_external_identifier")
      assignment["quiz_migration_id"] = get_node_val(meta_doc, "quiz_identifierref")
      assignment["workflow_state"] = get_node_val(meta_doc, "workflow_state") if meta_doc.at_css("workflow_state")
      assignment["external_tool_migration_id"] = get_node_val(meta_doc, "external_tool_identifierref") if meta_doc.at_css("external_tool_identifierref")
      assignment["external_tool_id"] = get_node_val(meta_doc, "external_tool_external_identifier") if meta_doc.at_css("external_tool_external_identifier")
      assignment["tool_setting"] = get_tool_setting(meta_doc) if meta_doc.at_css('tool_setting').present?
      assignment["resource_link_lookup_uuid"] = get_node_val(meta_doc, "resource_link_lookup_uuid") if meta_doc.at_css("resource_link_lookup_uuid")

      if meta_doc.at_css("saved_rubric_comments comment")
        assignment[:saved_rubric_comments] = {}
        meta_doc.css("saved_rubric_comments comment").each do |comment_node|
          assignment[:saved_rubric_comments][comment_node['criterion_id']] ||= []
          assignment[:saved_rubric_comments][comment_node['criterion_id']] << comment_node.text.strip
        end
      end
      if meta_doc.at_css("similarity_detection_tool")
        node = meta_doc.at_css("similarity_detection_tool")
        similarity_settings = node.attributes.each_with_object({}) { |(k, v), h| h[k] = v.value }
        assignment[:similarity_detection_tool] = similarity_settings
      end

      ['title', "allowed_extensions", "grading_type", "submission_types", "external_tool_url", "external_tool_data_json", "turnitin_settings"].each do |string_type|
        val = get_node_val(meta_doc, string_type)
        assignment[string_type] = val unless val.nil?
      end
      ["turnitin_enabled", "vericite_enabled", "peer_reviews",
       "automatic_peer_reviews", "anonymous_peer_reviews", "freeze_on_copy",
       "grade_group_students_individually", "external_tool_new_tab",
       "rubric_hide_points", "rubric_hide_outcome_results", "rubric_use_for_grading",
       "rubric_hide_score_total", "has_group_category", "omit_from_final_grade",
       "intra_group_peer_reviews", "only_visible_to_overrides", "post_to_sis",
       "moderated_grading", "grader_comments_visible_to_graders",
       "anonymous_grading", "graders_anonymous_to_graders",
       "grader_names_visible_to_final_grader", "anonymous_instructor_annotations"].each do |bool_val|
        val = get_bool_val(meta_doc, bool_val)
        assignment[bool_val] = val unless val.nil?
      end
      ['due_at', 'lock_at', 'unlock_at', 'peer_reviews_due_at'].each do |date_type|
        val = get_time_val(meta_doc, date_type)
        assignment[date_type] = val
      end
      ['points_possible'].each do |f_type|
        val = get_float_val(meta_doc, f_type)
        assignment[f_type] = val unless val.nil?
      end
      ['position', 'allowed_attempts'].each do |i_type|
        assignment[i_type] = get_int_val(meta_doc, i_type)
      end
      assignment['peer_review_count'] = get_int_val(meta_doc, 'peer_review_count')
      assignment["grader_count"] = get_int_val(meta_doc, "grader_count")
      if meta_doc.at_css("assignment_overrides override")
        assignment[:assignment_overrides] = []
        meta_doc.css("assignment_overrides override").each do |override_node|
          override = {
            set_type: override_node["set_type"],
            set_id: override_node["set_id"],
            title: override_node["title"]
          }
          AssignmentOverride.overridden_dates.each do |field|
            next unless override_node.has_attribute?(field.to_s)

            override[field] = override_node[field.to_s]
          end
          assignment[:assignment_overrides] << override
        end
      end
      if meta_doc.at_css("post_policy")
        assignment[:post_policy] = { post_manually: get_bool_val(meta_doc, "post_policy post_manually") || false }
      end
      if meta_doc.at_css("line_items")
        assignment[:line_items] = meta_doc.css("line_items line_item").map do |li_node|
          {
            client_id: get_int_val(li_node, 'client_id'),
            coupled: get_bool_val(li_node, 'coupled'),
            extensions: get_node_val(li_node, 'extensions'),
            label: get_node_val(li_node, 'label'),
            resource_id: get_node_val(li_node, 'resource_id'),
            score_maximum: get_float_val(li_node, 'score_maximum'),
            tag: get_node_val(li_node, 'tag'),
          }.compact
        end
      end
      if meta_doc.at_css("annotatable_attachment_migration_id")
        assignment[:annotatable_attachment_migration_id] = get_node_val(meta_doc, "annotatable_attachment_migration_id")
      end
      assignment
    end

    private

    def get_tool_setting(meta_doc)
      {
        product_code: meta_doc.at_css('tool_setting tool_proxy').attribute('product_code').value,
        vendor_code: meta_doc.at_css('tool_setting tool_proxy').attribute('vendor_code').value,
        custom: meta_doc.css("tool_setting custom property").each_with_object({}) { |el, hash| hash[el.attr('name')] = el.text },
        custom_parameters: meta_doc.css("tool_setting custom_parameters property").each_with_object({}) { |el, hash| hash[el.attr('name')] = el.text }
      }
    end
  end
end
