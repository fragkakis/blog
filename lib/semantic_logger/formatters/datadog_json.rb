module SemanticLogger
  module Formatters
    class DatadogJson < SemanticLogger::Formatters::Json
      MANUALLY_HANDLED_PAYLOAD_KEYS = [:session_info, :category, :http].freeze
      DATADOG_LOG_FORMAT_ENABLED = ENV.fetch("DATADOG_LOG_FORMAT_ENABLED", "no") == "yes"

      LOGGING_CATEGORY_HTTP_INBOUND = "http_inbound"
      LOGGING_CATEGORY_HTTP_OUTBOUND = "http_outbound"
      LOGGING_CATEGORY_EXCEPTION = "exception"
      LOGGING_CATEGORY_SOURCE_CODE = "source_code"

      LOGGED_HTTP_HEADERS = %w[user-agent x-request-id cf-ray referer device-id].freeze

      def initialize(**args)
        super(time_key: :date, **args)
      end

      def application
        hash[:source] = "ATS"
      end

      def level
        hash[:level] = log.level
      end

      def duration
        return unless log.duration

        hash[:duration_ms] = log.duration
      end

      def context
        return unless log.payload&.respond_to?(:empty?) && !log.payload.empty?
        log_payload_except_handled_keys = log.payload.except(*MANUALLY_HANDLED_PAYLOAD_KEYS)
        return unless log_payload_except_handled_keys.any?
        hash[:context] = log_payload_except_handled_keys
      end

      def user
        return unless log.payload&.respond_to?(:empty?) && !log.payload.empty?
        return if log.payload[:session_info].blank?

        user_hash = {}
        user_hash["id"] = log.payload[:session_info]["user"]
        user_hash["uid"] = log.payload[:session_info]["user_uid"]
        user_hash["admin_id"] = log.payload[:session_info]["admin"] if log.payload[:session_info]["admin"].present?
        user_hash["account_subdomain"] = log.payload[:session_info]["account_subdomain"] if log.payload[:session_info]["account_subdomain"].present?

        hash[:usr] = user_hash if user_hash.present?
      end

      def http
        return unless http_inbound? || http_outbound?
        hash[:http] = log.payload[:http]
      end

      def category
        category = if log.exception
                     LOGGING_CATEGORY_EXCEPTION
                   elsif log.payload.present? && log.payload[:category]
                     # http_inbound, http_outbound
                     log.payload[:category]
                   else
                     LOGGING_CATEGORY_SOURCE_CODE
                   end

        hash[:category] = category
      end

      def job
        return if log.named_tags.blank?

        job_hash = if log.named_tags[:que_job_id].present?
                     {
                       id: log.named_tags[:que_job_id],
                       system: "active_job",
                       channel: log.named_tags[:queue],
                       component: log.named_tags[:component],
                       args: log.named_tags[:args]
                     }
                   elsif log.named_tags[:kafka_message_key].present?
                     {
                       id: log.named_tags[:kafka_message_key],
                       system: "kafka",
                       channel: log.named_tags[:topic],
                       component: log.named_tags[:component]
                     }
                   end

        hash[:job] = job_hash if job_hash.present?
      end

      def datadog_trace_information
        hash["dd.trace_id"] = ::Datadog::Tracing.correlation.trace_id if ::Datadog::Tracing.correlation.trace_id.present?
        hash["dd.debug_trace_id"] = rand(1..100)
      end

      # Returns log messages in Hash format
      def call(log, logger)
        self.hash = {}
        self.log = log
        self.logger = logger

        time
        host
        level
        category
        # pid
        # thread_name
        # file_name_and_line
        duration
        http
        job
        # tags
        # named_tags
        message
        context
        exception
        datadog_trace_information
        # metric
        user

        hash

        Oj.to_json(hash, {})
      end

      private

      def http_outbound?
        log.payload.present? && log.payload[:category] == LOGGING_CATEGORY_HTTP_OUTBOUND
      end

      def http_inbound?
        log.payload.present? && log.payload[:category] == LOGGING_CATEGORY_HTTP_INBOUND
      end
    end
  end
end
