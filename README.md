# Tweet Synthesizer
This tool is a ruby script that will fetch tweets from a Twitter user and condense them into files.

# Prerequisites
- You have access to the [Twitter API](https://developer.twitter.com/en/docs/twitter-api), i.e. you have a Bearer Token. See [Getting Access](https://developer.twitter.com/en/docs/twitter-api/getting-started/getting-access-to-the-twitter-api) to get started.
- You have the [Faraday HTTP Client](https://lostisland.github.io/faraday) gem installed: `gem install faraday`

# Commands
## Fetch Tweets
Run `ruby main.rb` to view usage options.

Example Use
```bash
export TWITTER_API_BEARER_TOKEN=AAABBBCCCDDD
ruby main.rb jack -o ~/tweets --max-results 50 --verbose --dry-run
ruby main.rb jack -o ~/tweets --max-results 50 --verbose
```

## Update Tweets for Users
Run `ruby update.rb` to view usage options.

Example Use
```bash
# Setup input file
echo "jack, 1247616214769086465" >> input.csv

export TWITTER_API_BEARER_TOKEN=AAABBBCCCDDD
ruby update.rb --dry-run --verbose -i input.csv -o ~/tweets --max-results 50
ruby update.rb --verbose -i input.csv -o ~/tweets --max-results 50
```

# Use Case
This tool is helping me synthesize tweets in https://github.com/petermeglis/twitter-brain
