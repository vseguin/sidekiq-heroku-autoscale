# frozen_string_literal: true

module Sidekiq
  module HerokuAutoscale
    class PollInterval
      def initialize(method_name, before_update: 0, after_update: 0)
        @method_name = method_name
        @before_update = before_update
        @after_update = after_update
        @requests = {}
      end

      def call(process)
        return unless process

        @requests[process.name] ||= process
        poll!
      end

      def poll!
        @poll ||= Thread.new do
          while @requests.size.positive?
            sleep(@before_update) if @before_update.positive?
            @requests.reject! { |_, p| p.send(@method_name) }
            sleep(@after_update) if @after_update.positive?
          end
        ensure
          @poll = nil
        end
      end
    end
  end
end
