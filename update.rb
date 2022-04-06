require 'optparse'

DEFAULT_TWEET_DIRECTORY = "./tweets"
DEFAULT_MAX_TWEET_RESULTS = 50

# Options Parsing
def parse_options
  # Set defaults
  options = {
    max_results: DEFAULT_MAX_TWEET_RESULTS
  }

  OptionParser.new do |opt|
    opt.on('-i PATH', '--input-path PATH') { |o| options[:input_path] = o }
    opt.on('-o DIRECTORY', '--output-directory DIRECTORY') { |o| options[:output_directory] = o }
    opt.on('--max-results MAX_RESULTS') { |o| options[:max_results] = o.to_i }
    opt.on('--dry-run') { |o| options[:dry_run] = o }
    opt.on('--verbose') { |o| options[:verbose] = o }
  end.parse!

  options
end

OPTIONS = parse_options

# Update
def usage
"""
Takes input from a file and runs the main.rb fetch tweets script for each user and tweet ID.

Usage: ruby update.rb --input-path <file_path> [options]
Required Options:
  -i --input-path <file_path>: Path to file containing usernames and tweet IDs to update (see format below).
Options:
  -o --output_directory <file_path>: Path to directory to dump tweet files. Creates the directory if it doesn't exist. Defaults to #{DEFAULT_TWEET_DIRECTORY}
  --max-results <max_results>: Maximum number of tweets to retrieve per user. Defaults to #{DEFAULT_MAX_TWEET_RESULTS}
  --dry-run: Don't actually run subcommands or write to file.
  --verbose: Output more information.
Input file format:
  <twitter_username>, <last_tweet_id>
  <twitter_username>, <last_tweet_id>
  ...
"""
end

def update
  if OPTIONS[:input_path].nil?
    puts usage
    exit
  end
  
  if OPTIONS[:dry_run]
    puts "Running in dry-run mode. Does not run subcommand and does not write to file."
  end

  log("Using input file: #{OPTIONS[:input_path]}")

  updates_array = read_updates_from_file(OPTIONS[:input_path])

  updates_array.each do |username, tweet_id|
    log("Updating #{username} after tweet ID #{tweet_id}")

    update_tweets(username, tweet_id)
  end
end

def read_updates_from_file(file_path)
  updates_array = []
  log("Reading from input file...")

  File.open(file_path, 'r') do |file|
    file.each_line do |line|
      username, tweet_id = line.gsub(/\s+/, "").split(',')
      log("#{username}, #{tweet_id}")
      updates_array << [username, tweet_id]
    end
  end

  updates_array
end

def update_tweets(username, tweet_id)  
  command = "ruby main.rb #{username} "

  if OPTIONS[:dry_run]
    command += "--dry-run "
  end

  if OPTIONS[:verbose]
    command += "--verbose "
  end

  if OPTIONS[:output_directory]
    command += "--output-directory #{OPTIONS[:output_directory]} "
  end

  if OPTIONS[:max_results]
    command += "--max-results #{OPTIONS[:max_results]} "
  end

  command += "--since-id #{tweet_id} "

  if OPTIONS[:dry_run]
    log "Would now run the command: `#{command}`"
  else
    log "Running command: `#{command}`"

    system(command)
  end
end

# Logging
def log(message)
  puts message if OPTIONS[:verbose]
end

# Run the script
update()
