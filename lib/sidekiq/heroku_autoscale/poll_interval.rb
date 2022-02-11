# frozen_string_literal: true

module Sidekiq
  module HerokuAutoscale
    class PollInterval
      attr_reader :requests, :poll

      def initialize(method_name, before_update: 0, after_update: 0)
        @method_name = method_name
        @before_update = before_update
        @after_update = after_update
        @semaphore = Mutex.new
        @requests = {}
      end

      def call(process)
        return unless process

        @semaphore.synchronize do
          @requests[process.name] ||= process
        end

        poll!
      end

      def poll!
        @poll ||= Thread.new do
          while @requests.any?
            sleep(@before_update) if @before_update.positive?

            @semaphore.synchronize do
              @requests.reject! { |_, process| process.public_send(@method_name) }
            end

            sleep(@after_update) if @after_update.positive?
          end
        ensure
          @poll = nil
        end
      end
    end
  end
end
