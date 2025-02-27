# frozen_string_literal: true

#
# Copyright (C) 2013 - present Instructure, Inc.
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

# @API Feature Flags
#
# Manage optional features in Canvas.
#
#  _Deprecated_[2016-01-15] FeatureFlags previously had a locking_account_id field;
#  it was never used, and has been removed. It is still included in API responses
#  for backwards compatibility reasons. Its value is always null.
#
# @model Feature
#     {
#       "id": "Feature",
#       "description": "",
#       "properties": {
#         "feature": {
#           "description": "The symbolic name of the feature, used in FeatureFlags",
#           "example": "fancy_wickets",
#           "type": "string"
#         },
#         "display_name": {
#           "description": "The user-visible name of the feature",
#           "example": "Fancy Wickets",
#           "type": "string"
#         },
#         "applies_to": {
#           "description": "The type of object the feature applies to (RootAccount, Account, Course, or User):\n * RootAccount features may only be controlled by flags on root accounts.\n * Account features may be controlled by flags on accounts and their parent accounts.\n * Course features may be controlled by flags on courses and their parent accounts.\n * User features may be controlled by flags on users and site admin only.",
#           "example": "Course",
#           "type": "string",
#           "allowableValues": {
#             "values": [
#               "Course",
#               "RootAccount",
#               "Account",
#               "User"
#             ]
#           }
#         },
#         "enable_at": {
#           "description": "The date this feature will be globally enabled, or null if this is not planned. (This information is subject to change.)",
#           "example": "2014-01-01T00:00:00Z",
#           "type": "datetime"
#         },
#         "feature_flag": {
#           "description": "The FeatureFlag that applies to the caller",
#           "example": {"feature": "fancy_wickets", "state": "allowed"},
#           "$ref": "FeatureFlag"
#         },
#         "root_opt_in": {
#           "description": "If true, a feature that is 'allowed' globally will be 'off' by default in root accounts. Otherwise, root accounts inherit the global 'allowed' setting, which allows sub-accounts and courses to turn features on with no root account action.",
#           "example": true,
#           "type": "boolean"
#         },
#         "beta": {
#           "description": "Whether the feature is a beta feature. If true, the feature may not be fully polished and may be subject to change in the future.",
#           "example": true,
#           "type": "boolean"
#         },
#         "pending_enforcement": {
#           "description": "Whether the feature is nearing completion and will be finalized at an upcoming date.",
#           "example": true,
#           "type": "boolean"
#         },
#         "autoexpand": {
#           "description": "Whether the details of the feature are autoexpanded on page load vs. the user clicking to expand.",
#            "example": true,
#            "type": "boolean"
#          },
#         "release_notes_url": {
#           "description": "A URL to the release notes describing the feature",
#           "example": "http://canvas.example.com/release_notes#fancy_wickets",
#           "type": "string"
#         }
#       }
#     }
# @model FeatureFlag
#     {
#       "id": "FeatureFlag",
#       "description": "",
#       "properties": {
#         "context_type": {
#           "description": "The type of object to which this flag applies (Account, Course, or User). (This field is not present if this FeatureFlag represents the global Canvas default)",
#           "example": "Account",
#           "type": "string",
#           "allowableValues": {
#             "values": [
#               "Course",
#               "Account",
#               "User"
#             ]
#           }
#         },
#         "context_id": {
#           "description": "The id of the object to which this flag applies (This field is not present if this FeatureFlag represents the global Canvas default)",
#           "example": 1038,
#           "type": "integer"
#         },
#         "feature": {
#           "description": "The feature this flag controls",
#           "example": "fancy_wickets",
#           "type": "string"
#         },
#         "state": {
#           "description": "The policy for the feature at this context.  can be 'off', 'allowed', 'allowed_on', or 'on'.",
#           "example": "allowed",
#           "type": "string",
#           "allowableValues": {
#             "values": [
#               "off",
#               "allowed",
#               "allowed_on",
#               "on"
#             ]
#           }
#         },
#         "locked": {
#           "description": "If set, this feature flag cannot be changed in the caller's context because the flag is set 'off' or 'on' in a higher context",
#           "type": "boolean",
#           "example": false
#         }
#       }
#     }
#
class FeatureFlagsController < ApplicationController
  include Api::V1::FeatureFlag

  before_action :get_context

  # @API List features
  #
  # A paginated list of all features that apply to a given Account, Course, or User.
  #
  # @example_request
  #
  #   curl 'http://<canvas>/api/v1/courses/1/features' \
  #     -H "Authorization: Bearer <token>"
  #
  # @returns [Feature]
  def index
    if authorized_action(@context, @current_user, :read)
      route = polymorphic_url([:api_v1, @context, :features])
      features = Feature.applicable_features(@context, type: params[:type])
      features = Api.paginate(features, self, route)

      skip_cache = @context.grants_right?(@current_user, session, :manage_feature_flags)
      @context.feature_flags.load if skip_cache

      flags = features.map { |fd|
        @context.lookup_feature_flag(fd.feature,
                                     override_hidden: Account.site_admin.grants_right?(@current_user, session, :read),
                                     skip_cache: skip_cache,
                                     # Hide flags that are forced ON at a higher level
                                     # Undocumented flag for frontend use only
                                     hide_inherited_enabled: params[:hide_inherited_enabled])
      }.compact

      render json: flags.map { |flag| feature_with_flag_json(flag, @context, @current_user, session) }
    end
  end

  # @API List enabled features
  #
  # A paginated list of all features that are enabled on a given Account, Course, or User.
  # Only the feature names are returned.
  #
  # @example_request
  #
  #   curl 'http://<canvas>/api/v1/courses/1/features/enabled' \
  #     -H "Authorization: Bearer <token>"
  #
  # @example_response
  #
  #   ["fancy_wickets", "automatic_essay_grading", "telepathic_navigation"]
  def enabled_features
    if authorized_action(@context, @current_user, :read)
      features = Feature.applicable_features(@context).map { |fd| @context.lookup_feature_flag(fd.feature) }.compact
                        .select(&:enabled?).map(&:feature)
      render json: features
    end
  end

  # @API List environment features
  #
  # Return a hash of global feature settings that pertain to the
  # Canvas user interface. This is the same information supplied to the
  # web interface as +ENV.FEATURES+.
  #
  # @example_request
  #
  #   curl 'http://<canvas>/api/v1/features/environment' \
  #     -H "Authorization: Bearer <token>"
  #
  # @example_response
  #
  #   { "telepathic_navigation": true, "fancy_wickets": true, "automatic_essay_grading": false }
  #
  def environment
    render json: cached_js_env_account_features
  end

  # @API Get feature flag
  #
  # Get the feature flag that applies to a given Account, Course, or User.
  # The flag may be defined on the object, or it may be inherited from a parent
  # account. You can look at the context_id and context_type of the returned object
  # to determine which is the case. If these fields are missing, then the object
  # is the global Canvas default.
  #
  # @example_request
  #
  #   curl 'http://<canvas>/api/v1/courses/1/features/flags/fancy_wickets' \
  #     -H "Authorization: Bearer <token>"
  #
  # @returns FeatureFlag
  def show
    if authorized_action(@context, @current_user, :read)
      return render json: { message: "missing feature parameter" }, status: :bad_request unless params[:feature].present?

      feature = params[:feature]
      raise ActiveRecord::RecordNotFound unless Feature.definitions.key?(feature.to_s)

      flag = @context.lookup_feature_flag(feature,
                                          override_hidden: Account.site_admin.grants_right?(@current_user, session, :read),
                                          skip_cache: @context.grants_right?(@current_user, session, :manage_feature_flags))
      raise ActiveRecord::RecordNotFound unless flag

      render json: feature_flag_json(flag, @context, @current_user, session)
    end
  end

  # @API Set feature flag
  #
  # Set a feature flag for a given Account, Course, or User. This call will fail if a parent account sets
  # a feature flag for the same feature in any state other than "allowed".
  #
  # @argument state [String, "off"|"allowed"|"on"]
  #   "off":: The feature is not available for the course, user, or account and sub-accounts.
  #   "allowed":: (valid only on accounts) The feature is off in the account, but may be enabled in
  #               sub-accounts and courses by setting a feature flag on the sub-account or course.
  #   "on":: The feature is turned on unconditionally for the user, course, or account and sub-accounts.
  #
  # @example_request
  #
  #   curl -X PUT 'http://<canvas>/api/v1/courses/1/features/flags/fancy_wickets' \
  #     -H "Authorization: Bearer " \
  #     -F "state=on"
  #
  # @returns FeatureFlag
  def update
    if authorized_action(@context, @current_user, :manage_feature_flags)
      return render json: { message: "must specify feature" }, status: :bad_request unless params[:feature].present?

      feature_def = Feature.definitions[params[:feature]]
      return render json: { message: "invalid feature" }, status: :bad_request unless feature_def && feature_def.applies_to_object(@context)

      # check whether the feature is locked
      current_flag = @context.lookup_feature_flag(params[:feature], skip_cache: true)
      if current_flag
        return render json: { message: "higher account disallows setting feature flag" }, status: :forbidden if current_flag.locked?(@context)

        prior_state = current_flag.state
      end

      # require site admin privileges to unhide a hidden feature
      if !current_flag && feature_def.hidden?
        return render json: { message: "invalid feature" }, status: :bad_request unless Account.site_admin.grants_right?(@current_user, session, :read)

        prior_state = 'hidden'
      end

      new_attrs = { feature: params[:feature] }

      # check transition
      if params[:state].present?
        transitions = Feature.transitions(params[:feature], @current_user, @context, prior_state)
        if transitions[params[:state]] && transitions[params[:state]]['locked']
          return render json: { message: "state change not allowed" }, status: :forbidden
        end

        new_attrs[:state] = params[:state]
      end

      new_flag, saved = create_or_update_feature_flag(new_attrs, current_flag)
      if saved
        if prior_state != new_flag.state && feature_def.after_state_change_proc.is_a?(Proc)
          feature_def.after_state_change_proc.call(@current_user, @context, prior_state, new_flag.state)
        end
        render json: feature_flag_json(new_flag, @context, @current_user, session)
      else
        render json: new_flag.errors, status: :bad_request
      end
    end
  end

  # @API Remove feature flag
  #
  # Remove feature flag for a given Account, Course, or User.  (Note that the flag must
  # be defined on the Account, Course, or User directly.)  The object will then inherit
  # the feature flags from a higher account, if any exist.  If this flag was 'on' or 'off',
  # then lower-level account flags that were masked by this one will apply again.
  #
  # @example_request
  #
  #   curl -X DELETE 'http://<canvas>/api/v1/courses/1/features/flags/fancy_wickets' \
  #     -H "Authorization: Bearer <token>"
  #
  # @returns FeatureFlag
  def delete
    if authorized_action(@context, @current_user, :manage_feature_flags)
      return render json: { message: "must specify feature" }, status: :bad_request unless params[:feature].present?

      flag = @context.feature_flags.find_by!(feature: params[:feature])
      prior_state = flag.state
      return render json: { message: "flag is locked" }, status: :forbidden if flag.locked?(@context)

      flag.current_user = @current_user # necessary step for audit log
      if flag.destroy
        feature_def = Feature.definitions[params[:feature]]
        feature_def.after_state_change_proc&.call(@current_user, @context, prior_state, feature_def.state)
      end
      render json: feature_flag_json(flag, @context, @current_user, session)
    end
  end

  private

  def create_or_update_feature_flag(attributes, current_flag = nil)
    FeatureFlag.unique_constraint_retry do
      new_flag = @context.feature_flags.find(current_flag.id) if current_flag &&
                                                                 !current_flag.default? && !current_flag.new_record? &&
                                                                 current_flag.context_type == @context.class.name && current_flag.context_id == @context.id
      new_flag ||= @context.feature_flags.build
      new_flag.assign_attributes(attributes)
      new_flag.current_user = @current_user # necessary step for audit log
      result = new_flag.save
      [new_flag, result]
    end
  end
end
