require 'optparse'
require 'time'

require_relative "../helpers/logger"

SORT_FIRST = :first
SORT_LAST = :last
SORTS = {
  first: SORT_FIRST,
  last: SORT_LAST
}

FIELD_ID = :id
FIELDS = {
  id: FIELD_ID
}

FILE_NAME_REGEX = /(?<timestamp>.*) - (?<username>\w+) - (?<text>.*).md/
TWEET_ID_REGEX = /Tweet\ ID\:\ (?<tweet_id>\d+)/

# Options Parsing
def parse_options
  # Set defaults
  options = {}

  OptionParser.new do |opt|
    opt.on('-u USERNAME', '--username USERNAME') { |o| options[:username] = o }
    opt.on('--export-results-path <file_path>') { |o| options[:export_results_path] = o }
    opt.on('--verbose') { |o| options[:verbose] = o }
  end.parse!

  options
end

OPTIONS = parse_options

# Search
def usage
"""
Searches through a directory of tweet files for a given field.

Usage: ruby commands/search.rb <sort> <field> <directory> [options]
Sort: first, last
Field: id
Options:
  -u --username <username>: Only search for files by this username.
  --export-results-path <file_path>: Export results to this path.
  --verbose: Output more information.
"""
end

def search
  @logger = Logger.new(verbose: OPTIONS[:verbose])

  sort = ARGV[0].to_sym
  if sort.nil? || SORTS[sort].nil?
    log(usage, force_verbose: true)
    exit
  end

  field = ARGV[1].to_sym
  if field.nil? || FIELDS[field].nil?
    log(usage, force_verbose: true)
    exit
  end

  directory = ARGV[2]
  if directory.nil?
    log(usage, force_verbose: true)
    exit
  end

  export_results = ""

  username = OPTIONS[:username]
  if !username.nil?
    log("Searching for #{username}.")
    output_field = search_for_username(sort, field, directory, username)
    export_results += "#{username}, #{output_field}\n"
  else
    log("Searching for all usernames.")
    usernames = find_all_usernames_in_directory(directory)
    usernames.each do |single_username|
      output_field = search_for_username(sort, field, directory, single_username)
      export_results += "#{single_username}, #{output_field}\n"
      log("\n")
    end
  end

  if OPTIONS[:export_results_path]
    File.open(OPTIONS[:export_results_path], 'w') do |f|
      f.write(export_results)
    end
  end

  log("search.rb Done!\n\n")
end

def find_all_usernames_in_directory(directory)
  # Format: { username: count }
  usernames_cache = {}

  Dir.glob("*-*-*.md", base: directory) do |filename|
    username = filename.match(FILE_NAME_REGEX)[:username]
    usernames_cache[username] ||= 0
    usernames_cache[username] += 1
  end

  names = usernames_cache.keys.sort_by { |name| name.downcase }

  log("Usernames: #{names}")

  names
end

def search_for_username(sort, field, directory, username)
  case sort
  when SORT_FIRST
    file_path = get_sorted_files_for_username(username, directory).first
  when SORT_LAST
    file_path = get_sorted_files_for_username(username, directory).last
  end

  log("Found file: #{file_path}", force_verbose: true)

  case field
  when FIELD_ID
    output = search_id(file_path)
  end

  log("Found field: #{output}", force_verbose: true)

  output
end

def get_sorted_files_for_username(username, directory)
  log("Searching for tweet files by #{username} in #{directory}.")

  # Format: { file_path: timestamp}
  file_cache = {}

  # Assumes files are named in this format: "<timestamp> - <username> - <text>.md"
  Dir.glob("*- #{username} -*.md", base: directory) do |filename|
    # log("Found #{filename}")

    file_path = File.join(directory, filename)

    timestamp = Time.parse(filename.split(' - ')[0])
    file_cache[file_path] = timestamp
  end

  sorted_cache = file_cache.sort_by { |_, timestamp| timestamp }
  sorted_files = sorted_cache.map { |file_path, _| file_path }

  # log("Sorted files:")
  sorted_files.each do |file_path|
    # log(file_path)
  end
  
  sorted_files
end

def search_id(file_path)
  File.open(file_path) do |f|
    tweet_id_string = f.grep(TWEET_ID_REGEX).first
    if tweet_id_string.nil?
      log("Could not find \"Tweet ID\" in #{file_path}")
    end

    return tweet_id_string.match(TWEET_ID_REGEX)[:tweet_id]
  end
end

def log(message, force_verbose: false)
  @logger.log("#{LOG_PREFIX} - #{message}", force_verbose: force_verbose)
end

# Run the script
search()
