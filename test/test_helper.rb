# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/pride'
require 'minitest/autorun'
require 'mock_redis'

require 'sidekiq/heroku_autoscale'

redis_conn = proc { MockRedis.new }

Sidekiq.configure_client do |config|
  config.redis = ConnectionPool.new(size: 5, &redis_conn)
end

Sidekiq.configure_server do |config|
  config.redis = ConnectionPool.new(size: 25, &redis_conn)
end

Sidekiq.logger = ::Logger.new($stdout)
Sidekiq.logger.level = ::Logger::ERROR

FIXTURES_PATH = File.expand_path('fixtures', __dir__)

class TestQueueSystem
  attr_accessor :total_work, :dynos

  def initialize(total_work: 0, dynos: 0)
    @total_work = total_work
    @dynos = dynos
  end

  def work?
    total_work.positive?
  end
end

class TestWorker
  include Sidekiq::Worker
end

class TestClient
  class List
    def list(_app)
      raise 'not implemented'
    end

    def update(_params)
      raise 'not implemented'
    end
  end

  def formation
    @formation ||= List.new
  end
end
