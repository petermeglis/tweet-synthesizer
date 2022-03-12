require 'faraday'
require 'faraday/net_http'
require 'optparse'

DEFAULT_TWEET_DIRECTORY = "./tweets"
DEFAULT_MAX_TWEET_RESULTS = 50
MAX_TWEET_RESULTS_PER_REQUEST = 100
MAX_TWEET_TITLE_CHAR_LENGTH = 75

# Options Parsing
def parse_options
  # Set defaults
  options = {
    output_directory: DEFAULT_TWEET_DIRECTORY,
    max_results: DEFAULT_MAX_TWEET_RESULTS
  }

  OptionParser.new do |opt|
    opt.on('-o DIRECTORY', '--output-directory DIRECTORY') { |o| options[:output_directory] = o }
    opt.on('--max-results MAX_RESULTS') { |o| options[:max_results] = o.to_i }
    opt.on('--after-id AFTER_ID') { |o| options[:after_id] = o }
    opt.on('--dry-run') { |o| options[:dry_run] = o }
    opt.on('--verbose') { |o| options[:verbose] = o }
  end.parse!

  options
end

OPTIONS = parse_options

# Main
def usage
"""
Usage: ruby main.rb <username> [options]
Options:
  -o --output_directory <file_path>: Path to directory to dump tweet files. Creates the directory if it doesn't exist. Defaults to #{DEFAULT_TWEET_DIRECTORY}
  --max-results <max_results>: Maximum number of tweets to retrieve. Defaults to #{DEFAULT_MAX_TWEET_RESULTS}
  --after-id <tweet_id>: Only get tweets older than this tweet_id
  --dry-run: Don't actually write to file
  --verbose: Output more information
Environment:
  TWITTER_API_BEARER_TOKEN must be set in the environment  
"""
end

def main
  username = ARGV[0]
  if username.nil?
    puts usage
    exit
  end

  if ENV['TWITTER_API_BEARER_TOKEN'].nil?
    puts "Error: TWITTER_API_BEARER_TOKEN must be set in the environment\n"
    puts usage
    exit
  end

  if OPTIONS[:dry_run]
    puts "Running in dry-run mode"
  end

  if !OPTIONS[:dry_run]
    unless Dir.exist?(OPTIONS[:output_directory])
      log("Creating file directory: #{OPTIONS[:output_directory]}")
      Dir.mkdir(OPTIONS[:output_directory])
    end
    log("Using file directory: #{OPTIONS[:output_directory]}")
  end

  conn = build_faraday_connection

  user_response = get_user(conn, username)
  user_id = user_response.body['data']['id']
  user_username = user_response.body['data']['username']

  tweets = get_user_tweets(conn, user_id)
  condensed_tweets = condense_threads(tweets)
  condensed_tweets.each do |tweet|
    # Skip tweets that are replies to other users
    next if !tweet['in_reply_to_user_id'].nil? && tweet['in_reply_to_user_id'] != user_id

    tweet_id = tweet['id']
    tweet_content = tweet['text']
    tweet_created_at = tweet['created_at']

    output_tweet_to_file(user_username, tweet_id, tweet_created_at, tweet_content)  
  end
end

# Tweet Parser Logic Helpers
def condense_threads(tweets)
  thread_cache = {}
  reply_tweets = []

  tweets.each do |tweet|
    if tweet['referenced_tweets'].nil?
      log("Tweet #{tweet['id']} is not a reply")
      thread_cache[tweet['id']] = tweet
    else
      log("Tweet #{tweet['id']} is a reply")
      reply_tweets << tweet
    end
  end

  reply_tweets.each do |tweet|
    referenced_tweet_id = tweet['referenced_tweets']&.first['id']
    
    if thread_cache[referenced_tweet_id].nil?
      log("Could not find referenced tweet #{referenced_tweet_id} in cache for tweet #{tweet['id']}")
      next
    end

    log("Combining tweet #{tweet['id']} with tweet #{referenced_tweet_id}")
    thread_cache[referenced_tweet_id]['text'] += "\n\n#{tweet['text']}"
  end

  thread_cache.values
end

def output_tweet_to_file(username, id, created_at, content)
  file_title = "#{created_at} - #{username} - #{generate_tweet_title(content)}"

  log("Writing to file: #{file_title}")

  body = "### Tweet\n#{content}"
  footer = "### Metadata\nTweet ID: #{id}\nCreated At: #{created_at}\n\n### Related\n\n"

  if !OPTIONS[:dry_run]
    File.open("#{OPTIONS[:output_directory]}/#{file_title}.md", "w") { |f| f.write "#{body}\n\n#{footer}" }
  end
end

def generate_tweet_title(content)
  content[0..MAX_TWEET_TITLE_CHAR_LENGTH].gsub(/[^0-9A-Za-z\s]|[\n]/, '')
end

# API Client Setup
def build_faraday_connection
  Faraday.new(
    url: 'https://api.twitter.com/2',
    headers: {'Authorization' => "Bearer #{ENV['TWITTER_API_BEARER_TOKEN']}"}
  ) do |f|
    f.response :json
    f.adapter :net_http
  end
end

# API Methods
def get_user(conn, username)
  conn.get("users/by/username/#{username}")
end

def get_user_tweets(conn, user_id)
  tweets = []
  options = {
    "tweet.fields": "created_at,in_reply_to_user_id",
    "max_results": MAX_TWEET_RESULTS_PER_REQUEST,
    "exclude": "retweets",
    "expansions": "referenced_tweets.id"
  }
  options.merge!(
    { "until_id": OPTIONS[:after_id]}
  ) if !OPTIONS[:after_id].nil?

  results = conn.get("users/#{user_id}/tweets", options)
  log("Fetched #{results.body['data'].length} tweets")
  
  tweets += results.body['data']
  pagination_token = results.body['meta']['next_token']
  
  log("Pagination token is #{pagination_token}")

  while !pagination_token.nil? && tweets.length < OPTIONS[:max_results]
    results = conn.get("users/#{user_id}/tweets", 
      {
        "tweet.fields": "created_at,in_reply_to_user_id",
        "max_results": MAX_TWEET_RESULTS_PER_REQUEST,
        "exclude": "retweets",
        "expansions": "referenced_tweets.id",
        "pagination_token": pagination_token
      }
    )
    log("Fetched #{results.body['data'].length} tweets")
    
    tweets += results.body['data']
    pagination_token = results.body['meta']['next_token']

    log("Pagination token is #{pagination_token}")
  end

  tweets[0...OPTIONS[:max_results]]
end

# Logging
def log(message)
  puts message if OPTIONS[:verbose]
end

# Run the script
main()
