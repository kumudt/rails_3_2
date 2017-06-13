require 'google/cloud/logging'

module Rails3App
  module Logging
    class RequestLogger < Logger
      BATCH_SIZE = 10

      def initialize service_name, project_id, keyfile
        super
        @service_name = service_name
        @logging = Google::Cloud::Logging.new project: project_id, keyfile: keyfile
        @async = @logging.async_writer
        @resource = @logging.resource "project", "project_id" => service_name
        @labels = {service: service_name}
      end

      def info message
        add_entry :INFO, message, caller_locations.find {|loc|  loc.path =~ /#{Rails.root}/}
      end

      def debug message
        add_entry :DEBUG, message, caller_locations.find {|loc|  loc.path =~ /#{Rails.root}/}
      end

      def warn message
        add_entry :WARNING, message, caller_locations.find {|loc|  loc.path =~ /#{Rails.root}/}
      end

      def error message
        add_entry :ERROR, message, caller_locations.find {|loc|  loc.path =~ /#{Rails.root}/}
      end

      def fatal message
        add_entry :CRITICAL, message, caller_locations.find {|loc|  loc.path =~ /#{Rails.root}/}
      end

      def unknown message
        add_entry :DEFAULT, message, caller_locations.find {|loc|  loc.path =~ /#{Rails.root}/}
      end

      def add severity, message = nil
        if message.nil?
          if block_given?
            message = yield
          else
            message = ''
          end
        end

        add_entry severity, message, caller_locations.find {|loc|  loc.path =~ /#{Rails.root}/}
      end


      def add_entry severity, message, loc
        if message.blank?
          return
        end

        entry_line = {
          time: Time.now,
          severity: severity,
          message: message
        }

        unless loc.nil?
          entry_line[:path] = loc.path.gsub(/^#{Rails.root}/, '')
          entry_line[:line] = loc.lineno
          entry_line[:function] = loc.label
        end

        current_req = Thread.current.thread_variable_get('current_request')
        if current_req.nil?
          write_entry entry_line
          return
        end

        current_req[:queue] << entry_line

        if current_req[:queue].size > BATCH_SIZE
          flush_entries
        end
      end


      def write_entry entry_line
        entry = @logging.entry

        entry.payload = entry_line[:message]
        entry.severity = entry_line[:severity]
        entry.timestamp = entry_line[:time]

        entry.source_location.file = entry_line[:path]
        entry.source_location.function = entry_line[:function]
        entry.source_location.line = entry_line[:line]

        @async.write_entries [entry], log_name: "#{@service_name}_log", resource: @resource, labels: @labels
      end


      def write_entries entries
        if entries.size < 1
          return
        end

        current_req = Thread.current.thread_variable_get('current_request')
        req = current_req[:req]
        last_entry = current_req[:last]

        entry_lines = []

        entries.each do |entry_line|
          entry = @logging.entry

          entry.http_request.method = req.request_method.upcase
          entry.http_request.referer = req.referer
          entry.http_request.remote_ip = req.ip
          entry.http_request.url = req.fullpath
          entry.http_request.size = req.content_length
          entry.http_request.user_agent = req.user_agent

          entry.operation.first = false
          entry.operation.id = req.uuid
          entry.operation.producer = "#{@service_name}##{ENV['RAILS_ENV']}"
          entry.operation.last = false

          if last_entry
            entry.http_request.status = current_req[:status]
            entry.http_request.response_size = current_req[:response_size]
          end

          entry.payload = entry_line[:message]
          entry.timestamp = entry_line[:time]
          entry.severity = entry_line[:severity]
          entry.source_location.file = entry_line[:path]
          entry.source_location.function = entry_line[:function]
          entry.source_location.line = entry_line[:line]

          entry_lines << entry
        end

        entry_lines[0].operation.first = current_req[:first]
        entry_lines[-1].operation.last = last_entry

        @async.write_entries entry_lines, log_name: "#{ENV['RAILS_ENV']}_log", resource: @resource, labels: @labels

        if current_req[:first]
          current_req[:first] = false
        end
      end

      def flush_entries
        current_req = Thread.current.thread_variable_get('current_request')
        unless current_req.nil?
          while current_req[:queue].size > 0
            write_entries current_req[:queue].shift(BATCH_SIZE)
          end
        end
      end
    end
  end
end
