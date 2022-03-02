require 'faraday'
require 'faraday/net_http'

TWEET_DIRECTORY = "./tweets"

# Usage: ruby main.rb
# TWITTER_API_BEARER_TOKEN must be set in the environment

def main
  conn = build_faraday_connection
  
  tweet_id = 123
  response = conn.get('tweets', { "expansions": "author_id", "user.fields": "name", "ids": tweet_id })
  tweet_content = response.body['data'][0]['text']
  tweet_author = response.body['includes']['users'][0]['name']

  output_tweet_to_file(tweet_author, tweet_content)
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

def output_tweet_to_file(author, content)
  Dir.mkdir(TWEET_DIRECTORY) unless Dir.exist?(TWEET_DIRECTORY)

  file_title = "#{Time.now.strftime("%F %T")} - #{author} - #{generate_tweet_title(content)}"
  File.open("#{TWEET_DIRECTORY}/#{file_title}", "w") { |f| f.write content }
end

def generate_tweet_title(content)
  content[0..50].gsub!(/[^0-9A-Za-z\s]/, '')
end

# Run the script
main()
