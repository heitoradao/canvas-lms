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

lib = (Class.new do
  include Api::V1::Outcome

  def api_v1_outcome_path(opts)
    "/api/v1/outcome/#{opts.fetch(:id)}"
  end
  s
  def polymorphic_path(*_args)
    '/test'
  end
end).new

RSpec.describe "Api::V1::Outcome" do
  before do
    course_with_teacher(active_all: true)
  end

  def new_outcome(creation_params = {})
    creation_params.reverse_merge!({
                                     :title => 'TMNT Beats',
                                     :calculation_method => 'decaying_average',
                                     :calculation_int => 65,
                                     :display_name => "Ninja Rap",
                                     :description => "Turtles with Vanilla Ice",
                                     :vendor_guid => "TurtleTime4002",
                                   })

    @outcome = LearningOutcome.create!(creation_params)
    @outcome
  end

  def new_outcome_link(creation_params = {}, course = @course)
    outcome = new_outcome(creation_params) # sets @outcome
    course.root_outcome_group.add_outcome(outcome)
  end

  context "json" do
    let(:outcome_params) do
      {
        :title => 'TMNT Beats',
        :calculation_method => 'decaying_average',
        :calculation_int => 65,
        :display_name => "Ninja Rap",
        :description => "Turtles with Vanilla Ice",
        :vendor_guid => "TurtleTime4002",
      }
    end

    context "outcome json" do
      let(:opts) do
        { rating_percents: [30, 40, 30] }
      end

      let(:check_outcome_json) do
        ->(outcome) do
          expect(outcome['title']).to eq(outcome_params[:title])
          expect(outcome['calculation_method']).to eq(outcome_params[:calculation_method])
          expect(outcome['calculation_int']).to eq(outcome_params[:calculation_int])
          expect(outcome['display_name']).to eq(outcome_params[:display_name])
          expect(outcome['description']).to eq(outcome_params[:description])
          expect(outcome['vendor_guid']).to eq(outcome_params[:vendor_guid])
          expect(outcome['assessed']).to eq(LearningOutcome.find(outcome['id']).assessed?)
          expect(outcome['has_updateable_rubrics']).to eq(
            LearningOutcome.find(outcome['id']).updateable_rubrics?
          )
          expect(outcome['ratings'].length).to eq 3
          expect(outcome['ratings'].map { |r| r['percent'] }).to eq [30, 40, 30]
        end
      end

      it "returns the json for an outcome" do
        check_outcome_json.call(lib.outcome_json(new_outcome(outcome_params), nil, nil, opts))
      end

      it "returns the json for multiple outcomes" do
        outcomes = []
        10.times { outcomes.push(new_outcome) }
        lib.outcomes_json(outcomes, nil, nil, opts).each { |o| check_outcome_json.call(o) }
      end

      describe "with the account_level_mastery_scales FF" do
        describe "enabled" do
          before do
            @course.root_account.enable_feature!(:account_level_mastery_scales)
            @course_proficiency = outcome_proficiency_model(@course)
            @course_calculation_method = outcome_calculation_method_model(@course)
            @account = @course.root_account
            @account_proficiency = outcome_proficiency_model(@account)
            @account_calculation_method = outcome_calculation_method_model(@account)
          end

          it "returns the outcome proficiency and calculation method values of the provided context" do
            json = lib.outcome_json(new_outcome({ **outcome_params, :context => @account }), nil, nil, context: @course)
            expect(json['calculation_method']).to eq(@course_calculation_method.calculation_method)
            expect(json['calculation_int']).to eq(@course_calculation_method.calculation_int)
            expect(json['ratings']).to eq(@course_proficiency.ratings_hash.map(&:stringify_keys))
          end
        end

        describe "disabled" do
          before do
            @course.root_account.disable_feature!(:account_level_mastery_scales)
            @proficiency = outcome_proficiency_model(@course)
            @calculation_method = outcome_calculation_method_model(@course)
          end

          it "ignores the resolved_outcome_proficiency and resolved_calculation_method of the provided context" do
            opts.merge!(context: @course)
            check_outcome_json.call(lib.outcome_json(new_outcome(({ **outcome_params, :context => @course })), nil, nil, opts))
          end
        end
      end
    end

    context "outcome links json" do
      let(:check_outcome_link_json) do
        ->(outcome, course, outcome_link) do
          expect(outcome_link['outcome']['id']).to eq(outcome.id)
          expect(outcome_link['outcome']['title']).to eq(outcome_params[:title])
          expect(outcome_link['outcome']['vendor_guid']).to eq(outcome_params[:vendor_guid])

          expect(outcome_link['context_type']).to eq("Course")
          expect(outcome_link['context_id']).to eq(course.id)
          expect(outcome_link['url']).to eq(lib.polymorphic_path)

          expect(outcome_link['outcome_group']['id']).to eq(course.root_outcome_group.id)
        end
      end

      it "returns the json for an outcome link" do
        outcome_link = new_outcome_link(outcome_params)
        check_outcome_link_json.call(@outcome, @course, lib.outcome_link_json(outcome_link, nil, nil))
      end

      it "returns the json for multiple outcome links" do
        course_with_teacher(active_all: true)  # sets @course
        outcome_links = 10.times.map { new_outcome_link(outcome_params, @course) }
        lib.outcome_links_json(outcome_links, nil, nil).each do |ol|
          check_outcome_link_json.call(
            LearningOutcome.find(ol["outcome"]["id"]),
            @course,
            ol
          )
        end
      end
    end
  end
end
