require 'sinatra/base'
require 'memcachier'
require "dalli"
require "rack-cache"
require 'redis'

if ENV["MEMCACHIER_USERNAME"]
  use Rack::Cache,
    verbose: true,
    metastore: Dalli::Client.new,
    entitystore: 'file:tmp/cache/rack/body'
end

class CoinCORS < Sinatra::Base
  configure do
    EXPIRE_TIME = 10 # How long is data cached in REDIS.

    uri = if ENV["REDISTOGO_URL"]
      URI.parse(ENV["REDISTOGO_URL"])
    else
      URI.parse('redis://localhost')
    end

    REDIS = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
  end

  get '/coinbase' do
    fetch :coinbase
  end

  def coinbase_fetch
    buy = sell = 0

    begin
      if request = HTTParty.get('https://coinbase.com/api/v1/prices/buy') and request['amount']
        buy = request['amount']
      end
      if request = HTTParty.get('https://coinbase.com/api/v1/prices/sell') and request['amount']
        sell = request['amount']
      end
    rescue Errno::ECONNRESET
    end

    [buy, sell]
  end

  def fetch what
    unless REDIS.exists "#{what}:buy"
      # Fetch new stuff.
      buy, sell = send "#{what}_fetch"
      REDIS.mset "#{what}:buy", buy, "#{what}:sell", sell
      REDIS.expire "#{what}:buy", EXPIRE_TIME
      REDIS.expire "#{what}:sell", EXPIRE_TIME
    else
      # Fetch cached.
      buy, sell = REDIS.mget "#{what}:buy", "#{what}:sell"
    end

    cache_control :public, max_age: EXPIRE_TIME / 2
    content_type :json
    "{'sell': #{sell}, 'buy': #{buy}}"
  end
end
