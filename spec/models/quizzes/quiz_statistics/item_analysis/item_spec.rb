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

require_relative 'common'

describe Quizzes::QuizStatistics::ItemAnalysis::Item do
  describe ".from" do
    it "creates an item for a supported question type" do
      qq = { :question_type => "true_false_question", :answers => [] }
      expect(Quizzes::QuizStatistics::ItemAnalysis::Item.from(nil, qq)).not_to be_nil
    end

    it "does not create an item for an unsupported question type" do
      qq = { :question_type => "essay_question" }
      expect(Quizzes::QuizStatistics::ItemAnalysis::Item.from(nil, qq)).to be_nil
    end
  end

  before(:once) {
    simple_quiz_with_submissions %w{T T A}, %w{T T A}, %w{T F A}, %w{T T B}, %w{T T}
  }

  let(:item) {
    @summary = Quizzes::QuizStatistics::ItemAnalysis::Summary.new(@quiz)
    @summary.sorted_items.last
  }

  describe "#num_respondents" do
    it "returns all respondents" do
      expect(item.num_respondents).to eq 3 # one guy didn't answer
    end

    it "returns correct respondents" do
      expect(item.num_respondents(:correct)).to eq 2
    end

    it "returns incorrect respondents" do
      expect(item.num_respondents(:incorrect)).to eq 1
    end

    it "returns respondents in a certain bucket" do
      expect(item.num_respondents(:top)).to eq 1
      expect(item.num_respondents(:middle)).to eq 2
      expect(item.num_respondents(:bottom)).to eq 0 # there is a guy, but he didn't answer this question
    end

    it "evaluates multiple filters correctly" do
      expect(item.num_respondents(:top, :correct)).to eq 1
      expect(item.num_respondents(:top, :incorrect)).to eq 0
      expect(item.num_respondents(:middle, :correct)).to eq 1
      expect(item.num_respondents(:middle, :incorrect)).to eq 1
    end
  end

  describe "#variance" do
    it "matches R's output" do
      # population variance, not sample variance (thus the adjustment)
      # > v <- c(1, 1, 0)
      # > var(v)*2/3
      # [1] 0.2222222
      expect(item.variance).to be_approximately 0.2222222
    end
  end

  describe "#standard_deviation" do
    it "matches R's output" do
      # population sd, not sample sd (thus the adjustment)
      # > v <- c(1, 1, 0)
      # > sqrt(var(v)/3*2)
      # [1] 0.4714045
      expect(item.standard_deviation).to be_approximately 0.4714045
    end
  end

  describe "#difficulty_index" do
    it "returns the ratio of correct to incorrect" do
      expect(item.difficulty_index).to be_approximately 0.6666667
    end
  end

  describe "#point_biserials" do
    # > x<-c(3,2,2)
    # > cor(x,c(1,1,0))
    # [1] 0.5
    # > cor(x,c(0,0,1))
    # [1] -0.5
    it "matches R's output" do
      expect(item.point_biserials).to be_approximately [0.5, -0.5, nil, nil]
    end
  end
  let(:no_dev_item) do
    simple_quiz_with_submissions %w|T T|, %w|T T|, %w|T T|, %w|T T|
    @summary = Quizzes::QuizStatistics::ItemAnalysis::Summary.new(@quiz)
    @summary.sorted_items.last
  end

  it "explodes when the standard deviation is 0" do
    expect(no_dev_item.point_biserials).to eq [nil, nil]
  end
end
