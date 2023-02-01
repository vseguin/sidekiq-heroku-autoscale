# frozen_string_literal: true

require 'bundler/setup'
require 'minitest/pride'
require 'minitest/autorun'
require 'mock_redis'

require 'sidekiq/heroku_autoscale'

logger = ::Logger.new($stdout)
logger.level = ::Logger::ERROR

Sidekiq.configure_client do |config|
  config.logger = logger
end

Sidekiq.configure_server do |config|
  config.logger = logger
end

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

# Helper class to mock `Process` instances to test `PollInterval`
TestPollIntervalProcess = Struct.new(:name, :rejectable, keyword_init: true) do
  alias_method :reject?, :rejectable
end
