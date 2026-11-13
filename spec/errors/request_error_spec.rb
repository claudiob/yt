require 'spec_helper'
require 'yt/errors/request_error'

describe Yt::Errors::RequestError do
  subject(:error) { raise Yt::Errors::RequestError, params }
  let(:params) { {} }
  let(:msg) { %r{^A request to YouTube API failed} }

  describe '#exception' do
    it { expect{error}.to raise_error msg }

    context 'given the exception includes sensitive data' do
      let(:body) { 'some secret token' }
      let(:curl) { 'curl -H "Authorization: secret-token"' }
      let(:params) { {response_body: body, request_curl: curl}.to_json }

      describe 'given a log level of :debug or :devel' do
        before do
          config = Yt.configuration
          allow(config).to receive(:log_level).and_return(:debug)
        end
        specify 'exposes sensitive data' do
          expect{error}.to raise_error do |error|
            expect(error.message).to include 'secret'
          end
        end
      end

      %i(debug devel info).each do |log_level|
        describe "given a log level of :#{log_level}" do
          before do
            config = Yt.configuration
            allow(config).to receive(:log_level).and_return(log_level)
          end
          specify 'keeps sensitive data out of to_s, inspect and interpolation' do
            expect{error}.to raise_error do |error|
              expect(error.to_s).to eq 'A request to YouTube API failed'
              expect(error.inspect).not_to include 'secret'
              expect("failed: #{error}").not_to include 'secret'
            end
          end
        end
      end

      describe 'given a different log level' do
        before do
          config = Yt.configuration
          allow(config).to receive(:log_level).and_return(:info)
        end
        specify 'hides sensitive data' do
          expect{error}.to raise_error do |error|
            expect(error.message).not_to include 'secret'
          end
        end
      end
    end
  end
end

describe Yt::Error do
  let(:msg) { %r{^A request to YouTube API failed} }

  describe '#exception' do
    it { expect{raise Yt::Error}.to raise_error msg }
  end
end
