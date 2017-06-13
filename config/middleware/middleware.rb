require_relative 'custom_logger'

module Rails3App
  module Logging
    class Middleware

      def initialize app, service_name: '', logger: nil
        @app = app
        @service_name = service_name
        @logger = logger
      end

      def call env
        req = ActionDispatch::Request.new(env)

        current_req = {
          req: req,
          start_time: Time.now,
          first: true,
          last: false,
          queue: []
        }

        Thread.current.thread_variable_set("current_request", current_req)

        @logger.info "Request Started"

        begin
          status, headers, response = @app.call env

          body = ''
          response.each{ |s| body << s.to_s }

          current_req[:status] = status
          current_req[:response_size] = body.length

          [status, headers, response]
        ensure
          current_req[:end_time] = Time.now
          current_req[:last] = true

          @logger.info "Request Ended"

          @logger.flush_entries

          Thread.current.thread_variable_set("current_request", nil)
        end
      end
    end
  end
end
