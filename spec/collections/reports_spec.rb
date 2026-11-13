require 'spec_helper'
require 'yt/collections/reports'
require 'yt/models/content_owner'
require 'yt/models/video'
require 'yt/models/channel'

describe Yt::Collections::Reports do
  subject(:reports) { Yt::Collections::Reports.new(parent: content_owner).tap{|reports| reports.metrics = {views: Integer}} }
  let(:content_owner) { Yt::ContentOwner.new owner_name: 'any-name' }
  let(:error){ {reason: reason, message: message} }
  let(:msg) { {response_body: {error: {errors: [error]}}}.to_json }

  before do
    allow(reports).to receive(:retry_time).and_return(0)
  end

  describe '#within' do
    let(:result) { reports.within Range.new(5.days.ago, 4.days.ago), nil, nil, :day, nil, nil }
    context 'given the request raises error 400 with "Invalid Query" message' do
      let(:reason) { 'badRequest' }
      let(:message) { 'Invalid query. Query did not conform to the expectations' }
      before { expect(reports).to receive(:list).once.and_raise Yt::Error, msg }
      let(:try_again) { expect(reports).to receive(:list).at_least(:once) }

      context 'every time' do
        before { try_again.and_raise Yt::Error, msg }
        it { expect{result}.to fail }
      end

      context 'but returns a success code 2XX the second time' do
        before { try_again.and_return [views: {total: 20}] }
        it { expect{result}.not_to fail }
      end
    end
  end

  describe '#reports_params' do
    subject(:reports) { Yt::Collections::Reports.new(parent: video) }
    let(:video) { Yt::Video.new id: 'any-id', auth: content_owner }
    let(:params) { reports.send :reports_params }
    before do
      reports.metrics = {views: Integer, engaged_views: Integer, estimated_minutes_watched: Integer}
      reports.instance_variable_set :@days_range, Range.new(5.days.ago, 4.days.ago)
      reports.instance_variable_set :@dimension, dimension
    end

    [:related_video, :search_term, :referrer, :embedded_player_location].each do |top|
      context "given the top 25 by #{top}" do
        let(:dimension) { top }
        it { expect(params['sort']).to eq '-views' }
      end
    end

    context 'given the reports by video' do
      let(:dimension) { :video }
      it { expect(params['sort']).to eq '-views,engagedViews,estimatedMinutesWatched' }
    end

    context 'given the reports by video sorted by one metric and limited' do
      let(:dimension) { :video }
      before do
        reports.sort = :estimated_minutes_watched
        reports.limit = 5
      end
      it { expect(params['sort']).to eq '-estimatedMinutesWatched' }
      it { expect(params['maxResults']).to eq 5 }
    end

    context 'given a limit by search term' do
      let(:dimension) { :search_term }
      before { reports.limit = 8 }
      it { expect(params['maxResults']).to eq 8 }
      it { expect(params['sort']).to eq '-views' }
    end
  end

  describe 'reports(sort:)' do
    let(:channel) { Yt::Channel.new id: 'any-id', auth: content_owner }

    it 'must sort by one of the :only metrics' do
      expect{channel.reports only: [:views], by: :video, sort: :likes}.to raise_error ArgumentError, /sort must be one of the :only metrics/
    end
  end
end
