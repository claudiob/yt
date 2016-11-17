module Yt
  # Provides methods to interact with YouTube channels.
  # @see https://developers.google.com/youtube/v3/docs/channels
  class Channel
    # @param [Hash] options the options to initialize a Channel.
    # @option options [String] :id The unique ID of a YouTube channel.
    def initialize(options = {})
      @id = options[:id]
      @auth = options[:auth]
      @data = HashWithIndifferentAccess.new
      @data[:snippet] = options[:snippet] if options[:snippet]
      @data[:statistics] = options[:statistics] if options[:statistics]
      @data[:status] = options[:status] if options[:status]
    end

  ### COLLECTION

    # @return [Yt::Relation<Yt::Channel>] the channels matching the conditions.
    def self.where(conditions = {})
      @where ||= Relation.new(Channel) {|options| where_response options}
      @where.where conditions
    end

  ### ID

    # @return [String] the channel’s ID.
    def id
      @id
    end

  ### SNIPPET

    # @return [String] the channel’s title.
    def title
      snippet['title']
    end

    # @return [String] the channel’s description.
    def description
      snippet['description']
    end

    # def custom_url # not yet implemented, need 100 subs to test

    # @return [Time] the date and time that the channel was created.
    def published_at
      Time.parse snippet['publishedAt']
    end

    # Returns the URL of the channel’s thumbnail.
    # @param [Symbol, String] size The size of the channel’s thumbnail.
    # @return [String] if +size+ is +:default+, the URL of a 88x88px image.
    # @return [String] if +size+ is +:medium+, the URL of a 240x240px image.
    # @return [String] if +size+ is +:high+, the URL of a 800x800px image.
    # @return [nil] if the +size+ is none of the above.
    def thumbnail_url(size = :default)
      snippet['thumbnails'].fetch(size.to_s, {})['url']
    end

    # def default_language # not yet implemented, not sure how to set to test

    # def localized # not yet implemented

    # def country # not yet implemented, not sure how to set to test

  ### STATUS

    # @return [String] the privacy status of the channel. Valid values are:
    #   +"private"+, +"public"+, +"unlisted"+.
    def privacy_status
      status['privacyStatus']
    end

    # @return [Boolean] whether the channel data identifies a user that is
    #   already linked to either a YouTube username or a Google+ account.
    def is_linked
      status['isLinked']
    end

    # @return [String] whether the channel is eligible to upload videos that
    #   are more than 15 minutes long. Valid values are: +"allowed"+,
    #   +"disallowed"+, +"eligible"+, +"longUploadsUnspecified"+.
    # @note +"longUploadsUnspecified"+ is not documented by the YouTube API.
    # @see https://developers.google.com/youtube/v3/docs/channels#status.longUploadsStatus
    def long_upload_status
      status['longUploadsStatus']
    end

  ### STATISTICS

    # @return [<Integer>] the number of times the channel has been viewed.
    def view_count
      statistics['viewCount'].to_i
    end

    # @return [<Integer>] the number of comments for the channel.
    def comment_count
      statistics['commentCount'].to_i
    end

    # @return [<Integer>] the number of subscribers that the channel has.
    def subscriber_count
      statistics['subscriberCount'].to_i
    end

    # @return [<Boolean>] whether the channel’s subscriber count is publicly
    #   visible.
    def hidden_subscriber_count
      statistics['hiddenSubscriberCount']
    end

    # @return [<Integer>] the number of videos uploaded to the channel.
    def video_count
      statistics['videoCount'].to_i
    end

  ### ASSOCIATIONS

    # @return [Yt::Relation<Yt::Video>] the public videos of the channel.
    def videos
      @videos ||= Relation.new(Video) {|options| videos_response options}
    end

  ### CHANNEL ANALYTICS

    # @return [Hash<Symbol, Integer>] the total channel’s views.
    def views
      @views ||= {total: views_response.body['rows'].first.first.to_i}
    end

  ### CONTENT OWNER ANALYTICS

    # @return [Hash<Symbol, Integer>] the total channel’s impressions.
    def ad_impressions
      @ad_impressions ||= {total: ad_impressions_response.body['rows'].first.first.to_i}
    end

  ### OTHERS

    # Specifies which parts of the channel to fetch when hitting the data API.
    # @param [Array<Symbol, String>] parts The parts to fetch. Valid values
    #   are: +:snippet+, +:status+, and +:statistics+.
    # @return [Yt::Channel] itself.
    def select(*parts)
      @selected_data_parts = parts
      self
    end

    # @return [String] a representation of the Yt::Channel instance.
    def inspect
      "#<#{self.class} @id=#{@id}>"
    end

  private

  ### DATA

    def snippet
      data_part 'snippet'
    end

    def status
      data_part 'status'
    end

    def statistics
      data_part 'statistics'
    end

    def data_part(part)
      @data[part] || fetch_data(part)
    end

    def fetch_data(part)
      parts = @selected_data_parts || [part]
      if (items = data_response(parts).body['items']).any?
        parts.each{|part| @data[part] = items.first[part.to_s]}
        @data[part]
      else
        raise Errors::NoItems
      end
    end

    def data_response(parts)
      Net::HTTP.start 'www.googleapis.com', 443, use_ssl: true do |http|
        http.request data_request(parts)
      end.tap{|response| response.body = JSON response.body}
    end

    def data_request(parts)
      part = parts.join ','
      query = {key: Yt.configuration.api_key, id: @id, part: part}.to_param

      Net::HTTP::Get.new("/youtube/v3/channels?#{query}").tap do |request|
        request.initialize_http_header 'Content-Type' => 'application/json'
      end
    end

  ### COLLECTION

    def self.where_response(options = {})
      Net::HTTP.start 'www.googleapis.com', 443, use_ssl: true do |http|
        http.request where_request(options[:conditions].fetch(:id, []), options[:parts])
      end.tap{|response| response.body = JSON response.body}
    end

    def self.where_request(ids, parts)
      part = parts.join ','
      id = ids.join ','
      query = {key: Yt.configuration.api_key, id: id, part: part}.to_param

      Net::HTTP::Get.new("/youtube/v3/channels?#{query}").tap do |request|
        request.initialize_http_header 'Content-Type' => 'application/json'
      end
    end

  ### ASSOCIATIONS

    # /search only returns id and partial snippets. for any other part we
    # need a second call to /channels
    def videos_response(options = {})
      search = videos_search_response(options[:limit], options[:offset], options[:published_before])

      if options[:parts] == [:id]
        search.tap do |response|
          response.body['items'].map{|item| item['id'] = item['id']['videoId']}
        end
      else
        videos_list_response(options[:parts], search.body['items'].map{|item| item['id']['videoId']}).tap do |response|
          response.body['nextPageToken'] = search.body['nextPageToken']
        end
      end
    end

    def videos_search_response(limit, offset, published_before)
      Net::HTTP.start 'www.googleapis.com', 443, use_ssl: true do |http|
        http.request videos_search_request(limit, offset, published_before)
      end.tap{|response| response.body = JSON response.body}
    end

    def videos_search_request(limit, offset, published_before)
      query = {key: Yt.configuration.api_key, type: :video, channelId: @id, part: :id, maxResults: [limit, 50].min, pageToken: offset, order: :date}
      query[:publishedBefore] = published_before if published_before
      query = query.to_param
      p "QUERY #{query}"
      Net::HTTP::Get.new("/youtube/v3/search?#{query}").tap do |request|
        request.initialize_http_header 'Content-Type' => 'application/json'
      end
    end

    def videos_list_response(parts, video_ids)
      Net::HTTP.start 'www.googleapis.com', 443, use_ssl: true do |http|
        http.request videos_list_request(parts, video_ids)
      end.tap{|response| response.body = JSON response.body}
    end

    def videos_list_request(parts, video_ids)
      part = parts.join ','
      ids = video_ids.join ','
      query = {key: Yt.configuration.api_key, id: ids, part: part}.to_param
      Net::HTTP::Get.new("/youtube/v3/videos?#{query}").tap do |request|
        request.initialize_http_header 'Content-Type' => 'application/json'
      end
    end

  ### CHANNEL ANALYTICS

    def views_response
      Net::HTTP.start 'www.googleapis.com', 443, use_ssl: true do |http|
        http.request views_request
      end.tap{|response| response.body = JSON response.body}
    end

    def views_request
      query = {'metrics' => 'views', 'end-date' => Date.today.to_s, 'start-date' => '2005-02-01', 'ids' => "channel==#{@id}"}.to_param

      Net::HTTP::Get.new("/youtube/analytics/v1/reports?#{query}").tap do |request|
        request.initialize_http_header 'Content-Type' => 'application/json'
        request.add_field 'Authorization', "Bearer #{@auth.access_token}"
      end
    end

  ### CONTENT OWNER ANALYTICS

    def ad_impressions_response
      Net::HTTP.start 'www.googleapis.com', 443, use_ssl: true do |http|
        http.request ad_impressions_request
      end.tap{|response| response.body = JSON response.body}
    end

    def ad_impressions_request
      query = {'metrics' => 'adImpressions', 'end-date' => Date.today.to_s, 'start-date' => '2005-02-01', 'ids' => "contentOwner==#{@auth.id}", 'filters' => "channel==#{@id}"}.to_param

      Net::HTTP::Get.new("/youtube/analytics/v1/reports?#{query}").tap do |request|
        request.initialize_http_header 'Content-Type' => 'application/json'
        request.add_field 'Authorization', "Bearer #{@auth.access_token}"
      end
    end
  end
end