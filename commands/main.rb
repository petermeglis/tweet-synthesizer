require 'faraday'
require 'faraday/net_http'
require 'optparse'

require_relative "../helpers/logger"

DEFAULT_TWEET_DIRECTORY = "./tweets"
DEFAULT_MAX_TWEET_RESULTS = 50
MAX_TWEET_RESULTS_PER_REQUEST = 100
MAX_TWEET_TITLE_CHAR_LENGTH = 75

FILE_FORMAT_REGEX = /### Tweet\n(?<tweet_content>(.|\n)*)### Metadata\n(?<metadata>(.|\n)*)### Related\n(?<related>(.|\n)*)/
LOG_PREFIX = "main.rb"

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
    opt.on('--since-id SINCE_ID') { |o| options[:since_id] = o }
    opt.on('--dry-run') { |o| options[:dry_run] = o }
    opt.on('--verbose') { |o| options[:verbose] = o }
    opt.on('--export-logs-path FILE_PATH') { |o| options[:export_logs_path] = o }
    opt.on('--overwrite') { |o| options[:overwrite] = o }
    opt.on('--overwrite-only-tweet-content') { |o| options[:overwrite_only_tweet_content] = o }
  end.parse!

  options
end

OPTIONS = parse_options

# Main
def usage
"""
Fetches tweets from a user and outputs them to a file.

Usage: ruby commands/main.rb <username> [options]
Options:
  -o --output-directory <file_path>: Path to directory to dump tweet files. Creates the directory if it doesn't exist. Defaults to #{DEFAULT_TWEET_DIRECTORY}
  --max-results <max_results>: Maximum number of tweets to retrieve. Defaults to #{DEFAULT_MAX_TWEET_RESULTS}
  --after-id <tweet_id>: Only get tweets older than this tweet_id
  --since-id <tweet_id>: Only get tweets newer than this tweet_id
  --dry-run: Don't actually write to file
  --verbose: Output more information
  --export-logs-path <file_path>: Output logs from --verbose to file
  --overwrite: Overwrite existing files fully. Without this flag existing files will be skipped.
  --overwrite-only-tweet-content: Overwrite only the tweet text portion of existing files. Without this flag existing files will be skipped.
Environment:
  TWITTER_API_BEARER_TOKEN must be set in the environment  
"""
end

def main
  @logger = Logger.new(verbose: OPTIONS[:verbose], export_logs_path: OPTIONS[:export_logs_path])

  username = ARGV[0]
  if username.nil?
    log(usage, force_verbose: true)
    exit
  end

  if ENV['TWITTER_API_BEARER_TOKEN'].nil?
    log("Error: TWITTER_API_BEARER_TOKEN must be set in the environment\n", force_verbose: true)
    log(usage, force_verbose: true)
    exit
  end

  if OPTIONS[:dry_run]
    log("Running in dry-run mode. This will not write to file.", force_verbose: true)
  end

  if !OPTIONS[:dry_run]
    unless Dir.exist?(OPTIONS[:output_directory])
      log("Creating file directory: #{OPTIONS[:output_directory]}")
      Dir.mkdir(OPTIONS[:output_directory])
    end
  end
  log("Using file directory: #{OPTIONS[:output_directory]}")

  conn = build_faraday_connection

  user_response = get_user(conn, username)
  user_id = user_response.body['data']['id']
  user_username = user_response.body['data']['username']

  tweets = get_user_tweets(conn, user_id)
  if tweets.empty?
    log("No tweets found for user #{username}. Exiting...")
    return
  end
  condensed_tweets = condense_threads(tweets)
  condensed_tweets.each do |tweet|
    # Skip tweets that are replies to other users
    next if !tweet['in_reply_to_user_id'].nil? && tweet['in_reply_to_user_id'] != user_id

    tweet_id = tweet['id']
    tweet_content = tweet['text']
    tweet_created_at = tweet['created_at']

    output_tweet_to_file(user_username, tweet_id, tweet_created_at, tweet_content)  
  end

  log("main.rb Done!\n\n")
end

# Tweet Parser Logic Helpers

# Condenses tweets into a single tweet per thread.
# returns an array of tweets where each tweet's 'text'
# has the text from all tweets in the thread (if applicable).
def condense_threads(tweets)
  # tweet_cache stores the tweet data (id, text, created_at, etc.) for each tweet.
  # Format:
  # {
  #   tweet_id: tweet_data,
  #   tweet_id: tweet_data,
  #   ...
  # }
  tweet_cache = {}

  # thread_cache stores the inverse direction of the 'referenced_tweets' data
  # we get from the API.
  # Format:
  # {
  #   tweet_id: reply_tweet_id,
  #   tweet_id: reply_tweet_id,
  #   ...
  # }
  thread_cache = {}

  # Base tweets are tweets with no referenced tweets (i.e. are not replies).
  base_tweets = []

  tweets.each do |tweet|
    if tweet['referenced_tweets'].nil?
      # log("Tweet #{tweet['id']} is not a reply")

      base_tweets << tweet
    else
      # log("Tweet #{tweet['id']} is a reply")

      # For now, assume there's only one referenced tweet.
      referenced_tweet = tweet['referenced_tweets'].first
      thread_cache[referenced_tweet['id']] = tweet['id']
    end

    tweet_cache[tweet['id']] = tweet
  end

  base_tweets.each do |base_tweet|
    if thread_cache[base_tweet['id']].nil?
      log("#{base_tweet['id']} is a base tweet with no replies.")
      next
    end

    reply_tweet_id = thread_cache[base_tweet['id']]

    # Loop through the reply tweets in the thread.
    while !reply_tweet_id.nil? do
      current_tweet_in_thread = tweet_cache[reply_tweet_id]

      if current_tweet_in_thread.nil?
        # log("Reply tweet data not found in cache for #{reply_tweet_id}. This could be a reply to a tweet that was not retrieved.")
        break
      end

      log("Combining base tweet #{base_tweet['id']} with text from reply tweet #{current_tweet_in_thread['id']}.")
      base_tweet['text'] += "\n\n#{current_tweet_in_thread['text']}"

      reply_tweet_id = thread_cache[current_tweet_in_thread['id']]
    end
  end

  base_tweets
end

def output_tweet_to_file(username, id, created_at, tweet_content)
  file_title = "#{created_at} - #{username} - #{generate_tweet_title(tweet_content)}"
  file_path = "#{OPTIONS[:output_directory]}/#{file_title}.md"

  if !should_overwrite? && File.exist?(file_path)
    log("Skipping file because it already exists: #{file_path}")
    return
  end

  if should_overwrite? && File.exist?(file_path)
    log("Overwriting file: #{file_path}")
  end

  if !should_overwrite? && !File.exist?(file_path)
    log("Writing to file: #{file_title}")
  end

  body = "### Tweet\n#{tweet_content}"
  footer = "### Metadata\nTweet ID: #{id}\nCreated At: #{created_at}\n\n### Related\n\n"

  if !OPTIONS[:dry_run]
    if OPTIONS[:overwrite_only_tweet_content] && File.exist?(file_path)
      File.open(file_path, 'r+') do |file|
        previous_file_content = file.read
        previous_tweet_content = previous_file_content.match(FILE_FORMAT_REGEX)[:tweet_content]

        new_tweet_content = "#{tweet_content}\n\n"
        log("Replacing tweet content (previous/new): #{previous_tweet_content.length}/#{new_tweet_content.length}")

        new_file_content = previous_file_content.gsub(previous_tweet_content, new_tweet_content)

        file.rewind
        file.write(new_file_content)
      rescue => e
        log("Error overwriting tweet content: #{file_path}")
        log("Error: #{e.message}")
      end
    else
      File.open(file_path, "w") { |f| f.write "#{body}\n\n#{footer}" }
    end
  end
end

def should_overwrite?
  OPTIONS[:overwrite] || OPTIONS[:overwrite_only_tweet_content]
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
  log("Getting user: #{username}")
  results = conn.get("users/by/username/#{username}")
  log("Fetched user #{results.body['data']['username']} with id #{results.body['data']['id']}")
  results
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
  options.merge!(
    { "since_id": OPTIONS[:since_id]}
  ) if !OPTIONS[:since_id].nil?

  log("Getting tweets for user with id #{user_id}")
  results = conn.get("users/#{user_id}/tweets", options)

  log("Fetched #{results.body['meta']['result_count']} tweets")

  return [] if results.body['meta']['result_count'] == 0

  tweets += results.body['data']
  pagination_token = results.body['meta']['next_token']

  log("Pagination token is #{pagination_token}")

  while !pagination_token.nil? && tweets.length < OPTIONS[:max_results]
    new_options = options.merge({"pagination_token": pagination_token})
    results = conn.get("users/#{user_id}/tweets", new_options)

    log("Fetched #{results.body['data'].length} tweets")

    tweets += results.body['data']
    pagination_token = results.body['meta']['next_token']

    log("Pagination token is #{pagination_token}")
  end

  tweets[0...OPTIONS[:max_results]]
end

def log(message, force_verbose: false)
  @logger.log("#{LOG_PREFIX} - #{message}", force_verbose: force_verbose)
end

# Run the script
main()
