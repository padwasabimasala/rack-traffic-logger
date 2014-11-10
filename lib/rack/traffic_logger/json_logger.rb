require 'json'
require 'securerandom'

module Rack
  class TrafficLogger
    class JsonLogger

      # These environment properties will always be logged as part of request logs
      BASIC_ENV_PROPERTIES = %w[
        REQUEST_METHOD
        HTTPS
        SERVER_NAME
        SERVER_PORT
        PATH_INFO
        QUERY_STRING
        HTTP_VERSION
      ]

      attr_reader :app, :options

      def initialize(app, log_path, *options)
        @app = app
        @log_path = log_path
        @options = {}
        @status_options = {}
        options.each { |option| import_option option }
      end

      def call(env)
        Request.new(self).call env
      end

      def write(data)
        if @log_path.respond_to? :write
          @log_path.write data
        else
          File.write @log_path, data, mode: 'a', encoding: data.encoding
        end
      end

      private

      def import_option(option)
        case option
          when :request_bodies, :response_bodies, :request_headers, :response_headers
            @options[option] = true
          when :headers
            @options[:request_headers] = true
            @options[:response_headers] = true
          when :bodies
            @options[:request_bodies] = true
            @options[:response_bodies] = true
          when :get, :post, :put, :patch, :delete, :option, :head, :trace
            (@verb_filter ||= []) << option.to_s.upcase
          when Hash
            option.each { |k, v| import_option_pair k, v }
          else
            raise "Invalid option of type #{option.class.name} : #{option}"
        end
      end

      def import_option_pair(key, value)
        case key
          when :request_bodies, :response_bodies, :request_headers, :response_headers
            raise "Option #{key} must be boolean" unless [TrueClass, FalseClass].include? value.class
        end
      end

      class Request

        def initialize(logger)
          @logger = logger
          @options = logger.options
          @id = SecureRandom.hex 4
        end

        def call(env)
          log_request env
          @logger.app.call(env).tap { |response| log_response response }
        end

        private

        BASIC_AUTH_PATTERN = /^basic ([a-z\d+\/]+={0,2})$/i

        def log_request(env)
          log 'request' do |hash|
            if @options[:request_headers]
              hash.merge! env.reject { |_, v| v.respond_to? :read }
            else
              hash.merge! env.select { |k, _| JsonLogger::BASIC_ENV_PROPERTIES.include? k }
            end

            hash['BASIC_AUTH_USER'], hash['BASIC_AUTH_PASSWORD'] = $1.unpack('m').first.split(':', 2) if hash['HTTP_AUTHORIZATION'] =~ BASIC_AUTH_PATTERN

            input = env['rack.input']
            if input && @options[:request_bodies]
              add_body_to_hash input.read, env['CONTENT_ENCODING'] || env['HTTP_CONTENT_ENCODING'], hash
              input.rewind
            end
          end
        end

        def log_response(response)
          code, headers, body = response
          code = code.to_i
          headers = HeaderHash.new(headers) if @options[:response_headers] || @options[:response_bodies]
          log 'response' do |hash|
            hash['status_code'] = code
            hash['status_name'] = Utils::HTTP_STATUS_CODES[code]
            hash['headers'] = headers if @options[:response_headers]
            add_body_to_hash get_real_body(body), headers['Content-Encoding'], hash if @options[:response_bodies]
          end
        end

        # Rack allows response bodies to be a few different things. This method
        # ensures we get a string back.
        def get_real_body(body)

          # For bodies representing temporary files
          body = File.open(body.path, 'rb') { |f| f.read } if body.respond_to? :path

          # For bodies representing streams
          body = body.read.tap { body.rewind } if body.respond_to? :read

          # When body is an array (the common scenario)
          body = body.join if body.respond_to? :join

          # When body is a proxy
          body = body.body while Rack::BodyProxy === body

          # It should be a string now. Just in case it's not...
          body.to_s

        end

        def add_body_to_hash(body, encoding, hash)
          body = Zlib::GzipReader.new(StringIO.new body).read if encoding == 'gzip'
          body.force_encoding 'UTF-8'
          if body.valid_encoding?
            hash['body'] = body
          else
            hash['body_base64'] = [body].pack 'm0'
          end
        end

        def log(event)
          hash = {
              timestamp: Time.now,
              request_log_id: @id,
              event: event
          }
          yield hash rescue hash.merge! error: $!
          @logger.write JSON.generate hash
        end

      end

    end
  end
end
