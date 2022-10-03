require 'faraday'
require 'faraday/net_http'
require 'optparse'
require 'csv'

require_relative "../helpers/api_client"
require_relative "../helpers/logger"

DEFAULT_OUTPUT_FILE = "./tweets.csv"
DEFAULT_MAX_TWEET_RESULTS = 1000
MAX_TWEET_RESULTS_PER_REQUEST = 100

START_DATE_OPTION_FORMAT = /\d{4}-\d{2}-\d{2}/
CSV_HEADER_ROW = ["date_time", "handle", "tweet"]
LOG_PREFIX = "single_file.rb"

# Options Parsing
def parse_options
  # Set defaults
  options = {
    output_file: DEFAULT_OUTPUT_FILE,
    max_results: DEFAULT_MAX_TWEET_RESULTS
  }

  OptionParser.new do |opt|
    opt.on('-i FILE', '--input-file FILE') { |o| options[:input_file] = o }
    opt.on('-o FILE', '--output-file FILE') { |o| options[:output_file] = o }
    opt.on('--max-results MAX_RESULTS') { |o| options[:max_results] = o.to_i }
    opt.on('--start-date DATE') { |o| options[:start_date] = o }
    opt.on('--after-id AFTER_ID') { |o| options[:after_id] = o }
    opt.on('--since-id SINCE_ID') { |o| options[:since_id] = o }
    opt.on('--dry-run') { |o| options[:dry_run] = o }
    opt.on('--verbose') { |o| options[:verbose] = o }
    opt.on('--export-logs-path FILE_PATH') { |o| options[:export_logs_path] = o }
    opt.on('--overwrite') { |o| options[:overwrite] = o }
  end.parse!

  options
end

OPTIONS = parse_options

# Main
def usage
"""
Fetches tweets from a user (or list of users) and outputs their tweets to a CSV file.

Usage: ruby commands/single_file.rb <username> [options]
Required Options:
  -i --input-file <file_path>: Path to list of twitter handles to run on. Required only if <username> not given (see format below).
Options:
  -o --output-file <file_path>: Path to CSV file to dump tweets. Defaults to #{DEFAULT_OUTPUT_FILE}
  --max-results <max_results>: Maximum number of tweets to retrieve. Defaults to #{DEFAULT_MAX_TWEET_RESULTS}
  --start-date <date>: Only get tweets since this date. Format: YYYY-MM-DD
  --after-id <tweet_id>: Only get tweets older than this tweet_id
  --since-id <tweet_id>: Only get tweets newer than this tweet_id
  --dry-run: Don't actually write to file
  --verbose: Output more information
  --export-logs-path <file_path>: Output logs from --verbose to file
  --overwrite: Overwrite output file. If not passed, append to output file.
Environment:
  TWITTER_API_BEARER_TOKEN must be set in the environment
Input file format:
  <twitter_username>
  <twitter_username>
  ...
"""
end

def main
  @logger = Logger.new(verbose: OPTIONS[:verbose], export_logs_path: OPTIONS[:export_logs_path])
  @client = ApiClient.new(logger: @logger)

  # Get and parse usernames
  username_list = []
  if ARGV[0].nil?
    if OPTIONS[:input_file].nil?
      log(usage, force_verbose: true)
      exit
    else
      username_list += File.readlines(OPTIONS[:input_file], chomp: true)
    end
  else
    username_list << ARGV[0]
  end

  if username_list.empty?
    log(usage, force_verbose: true)
    exit
  end

  # Check environment
  if ENV['TWITTER_API_BEARER_TOKEN'].nil?
    log("Error: TWITTER_API_BEARER_TOKEN must be set in the environment\n", force_verbose: true)
    log(usage, force_verbose: true)
    exit
  end

  # Check start date option. Exit if you pass in a start_date and it doesn't match the format.
  if !OPTIONS[:start_date].nil? && !START_DATE_OPTION_FORMAT.match?(OPTIONS[:start_date])
    log("Error: --start-date format: YYYY-MM-DD")
    log(usage, force_verbose: true)
    exit
  end

  log("Using file: #{OPTIONS[:output_file]}")

  if OPTIONS[:dry_run]
    log("Running in dry-run mode. This will not write to file.", force_verbose: true)
  else
    if should_overwrite?
      log("Writing header row first")
      CSV.open(OPTIONS[:output_file], "w") { |f| f << CSV_HEADER_ROW }
    end
  end

  # Process
  for username in username_list
    find_and_write_tweets_for(username)
  end

  log("single_file.rb Done!\n\n")
end

# Tweet Parser Logic Helpers

def find_and_write_tweets_for(username)
  user_response = @client.get_user(username)
  user_id = user_response.body['data']['id']
  user_username = user_response.body['data']['username']

  tweets = @client.get_user_tweets(user_id, {
    start_time: formatted_start_date_time_option,
    after_id: OPTIONS[:after_id],
    since_id: OPTIONS[:since_id],
    max_results: OPTIONS[:max_results],
    max_tweet_results_per_request: MAX_TWEET_RESULTS_PER_REQUEST
  })
  if tweets.empty?
    log("No tweets found for user #{username}. Exiting...")
    return
  end
  condensed_tweets = condense_threads(tweets)
  condensed_tweets.each do |tweet|
    # Skip tweets that are replies to other users
    next if !tweet['in_reply_to_user_id'].nil? && tweet['in_reply_to_user_id'] != user_id

    tweet_content = tweet['text']
    tweet_created_at = tweet['created_at']

    output_tweet_to_file(user_username, tweet_created_at, tweet_content)  
  end
end

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

def output_tweet_to_file(username, created_at, tweet_content)
  if !OPTIONS[:dry_run]
    CSV.open(OPTIONS[:output_file], "a") { |f| f << [created_at, username, tweet_content] }
  else
    log("Would write to file: #{created_at}, #{username}, #{tweet_content}")
  end
end

def should_overwrite?
  OPTIONS[:overwrite]
end

def formatted_start_date_time_option
  OPTIONS[:start_date].nil? ? nil : "#{OPTIONS[:start_date]}T00:00:00Z"
end

def log(message, force_verbose: false)
  @logger.log("#{LOG_PREFIX} - #{message}", force_verbose: force_verbose)
end

# Run the script
main()
