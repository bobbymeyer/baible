# frozen_string_literal: true

# Drives a Training (docs/HANDOFF.md "The LoRA loop"): puts its set in
# ComfyUI's inputs and queues the training graph, then checks back until
# ComfyUI has saved the LoRA, the run fails, or it times out
# (ApplicationJob#poll_comfy), waiting out a ComfyUI that can't be reached
# as a batch does.
class TrainingJob < ApplicationJob
  discard_on ActiveJob::DeserializationError # the run was deleted
  waits_for_services do |job, error|
    job.arguments.first.fail!("#{error.message}. Tried for a day; train it again once it's back.")
  end

  def perform(training, client: Comfy.client)
    poll_comfy(training, client) do
      training.upload_set!(client)
      training.submit!(client)
    end
  end
end
