Datadog.configure do |c|
  c.tracing.instrument :rails, service_name: "blog"
end