# frozen_string_literal: true

# Drives a Trial: queues its test render and collects the picture, as a
# batch is driven (ApplicationJob#poll_comfy).
class TrialJob < ApplicationJob
  discard_on ActiveJob::DeserializationError
  waits_for_services do |job, error|
    job.arguments.first.fail!("#{error.message}. Tried for a day; try it again once it's back.")
  end

  def perform(trial, client: Comfy.client)
    poll_comfy(trial, client) { trial.submit!(client) }
  end
end
