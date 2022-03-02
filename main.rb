require 'faraday'
require 'faraday/net_http'

TWEET_DIRECTORY = "./tweets"

# Usage: ruby main.rb <username>
# TWITTER_API_BEARER_TOKEN must be set in the environment

def main
  username = ARGV[0]
  if username.nil?
    puts "Usage: ruby main.rb <username>"
    exit
  end

  conn = build_faraday_connection

  user_response = get_user(conn, username)
  user_id = user_response.body['data']['id']
  user_name = user_response.body['data']['name']

  tweets_response = get_user_tweets(conn, user_id)
  tweets_response.body['data'].each do |tweet|
    # Skip tweets that are replies to other users
    next if !tweet['in_reply_to_user_id'].nil? && tweet['in_reply_to_user_id'] != user_id

    tweet_content = tweet['text']
    tweet_created_at = tweet['created_at']

    output_tweet_to_file(user_name, tweet_created_at, tweet_content)  
  end
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

def get_user(conn, username)
  conn.get("users/by/username/#{username}")
end

def get_user_tweets(conn, user_id)
  conn.get("users/#{user_id}/tweets", 
    {
      "tweet.fields": "created_at,in_reply_to_user_id",
      "max_results": 15,
      "exclude": "retweets"
    }
  )
end

def output_tweet_to_file(author, created_at, content)
  Dir.mkdir(TWEET_DIRECTORY) unless Dir.exist?(TWEET_DIRECTORY)

  file_title = "#{created_at} - #{author} - #{generate_tweet_title(content)}"
  File.open("#{TWEET_DIRECTORY}/#{file_title}", "w") { |f| f.write content }
end

def generate_tweet_title(content)
  content[0..50].gsub(/[^0-9A-Za-z\s]|[\n]/, '')
end

# Run the script
main()
