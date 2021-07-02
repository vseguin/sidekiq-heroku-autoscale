# frozen_string_literal: true

module Sidekiq
  module HerokuAutoscale
    class Middleware
      def initialize(app)
        @app = app
      end

      def call(_worker_class, _item, queue, _ = nil)
        result = yield

        if (process = @app.process_for_queue(queue))
          process.ping!
        end

        result
      end
    end
  end
end
