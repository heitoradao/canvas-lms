# frozen_string_literal: true

#
# Copyright (C) 2021 - present Instructure, Inc.
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

module MicrosoftSync
  class GraphService
    class EducationClassesEndpoints < EndpointsBase
      # Yields (results, next_link) for each page, or returns first page of results if no block given.
      def list_education_classes(options = {}, &blk)
        get_paginated_list(
          'education/classes',
          quota: [1, 0],
          special_cases: [
            SpecialCase.new(
              400, /Education_ObjectType.*does not exist as.*property/,
              result: Errors::NotEducationTenant
            )
          ],
          **options, &blk
        )
      end

      def create_education_class(params)
        request(:post, 'education/classes', quota: [1, 1], body: params)
      end
    end
  end
end
