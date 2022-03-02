require 'faraday'
require 'faraday/net_http'

# Usage: ruby main.rb
# TWITTER_API_BEARER_TOKEN must be set in the environment

conn = Faraday.new(
  url: 'https://api.twitter.com/2',
  headers: {'Authorization' => "Bearer #{ENV['TWITTER_API_BEARER_TOKEN']}"}
) do |f|
  f.response :json
  f.adapter :net_http
end

tweet_id = 123
response = conn.get('tweets', { "expansions": "author_id", "user.fields": "name", "ids": tweet_id })
tweet_content = response.body['data'][0]['text']

timestamp = Time.now.strftime("%F %T")
tweet_author = response.body['includes']['users'][0]['name']
tweet_title = tweet_content[0..50].gsub!(/[^0-9A-Za-z\s]/, '')
file_title = "#{timestamp} - #{tweet_author} - #{tweet_title}"

directory_name = "./tweets"
Dir.mkdir(directory_name) unless Dir.exist?(directory_name)

File.open("#{directory_name}/#{file_title}", "w") { |f| f.write tweet_content }
