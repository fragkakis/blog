class ArticlesController < ApplicationController
  def index
    Rails.logger.debug("This is a debug log message")
    Rails.logger.info("This is an info log message")
    Rails.logger.info("trace id: #{::Datadog::Tracing.correlation.trace_id}")
  end
end
