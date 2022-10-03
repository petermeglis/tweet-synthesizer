require_relative "../helpers/logger"

class ApiClient
  LOG_PREFIX = "CLIENT"

  def initialize(logger: Logger.new)
    @connection = build_faraday_connection
    @logger = logger
  end

  # Returns data for a user.
  def get_user(username)
    log("Fetching user: #{username}")
    results = @connection.get("users/by/username/#{username}")
    log("Fetched user #{results.body['data']['username']} with id #{results.body['data']['id']}")
    results
  end

  # Returns an array of tweets.
  # @option after_id
  # @option since_id
  # @option max_results
  # @option max_tweet_results_per_request
  def get_user_tweets(user_id, options)
    start_time = options[:start_time]
    after_id = options[:after_id]
    since_id = options[:since_id]
    max_results = options[:max_results]
    max_tweet_results_per_request = options[:max_tweet_results_per_request]

    tweets = []
    request_options = {
      "tweet.fields": "created_at,in_reply_to_user_id",
      "max_results": max_tweet_results_per_request,
      "exclude": "retweets",
      "expansions": "referenced_tweets.id"
    }
    request_options.merge!(
      { "start_time": start_time}
    ) if !start_time.nil?
    request_options.merge!(
      { "until_id": after_id}
    ) if !after_id.nil?
    request_options.merge!(
      { "since_id": since_id}
    ) if !since_id.nil?
  
    log("Fetching tweets for user with id #{user_id}")
    results = @connection.get("users/#{user_id}/tweets", request_options)
  
    log("Fetched #{results.body['meta']['result_count']} tweets")
  
    return [] if results.body['meta']['result_count'] == 0
    
    tweets += results.body['data']
    pagination_token = results.body['meta']['next_token']
    
    log("Pagination token is #{pagination_token}")
  
    while !pagination_token.nil? && tweets.length < max_results
      new_request_options = request_options.merge({"pagination_token": pagination_token})
      results = @connection.get("users/#{user_id}/tweets", new_request_options)
  
      log("Fetched #{results.body['data'].length} tweets")
      
      tweets += results.body['data']
      pagination_token = results.body['meta']['next_token']
  
      log("Pagination token is #{pagination_token}")
    end
  
    tweets[0...max_results]
  end

  private

  def log(message)
    @logger.log("#{LOG_PREFIX} - #{message}")
  end

  def build_faraday_connection
    Faraday.new(
      url: 'https://api.twitter.com/2',
      headers: {'Authorization' => "Bearer #{ENV['TWITTER_API_BEARER_TOKEN']}"}
    ) do |f|
      f.response :json
      f.adapter :net_http
    end
  end
end
