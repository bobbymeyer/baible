# frozen_string_literal: true

# Drives a Training (docs/HANDOFF.md "The LoRA loop"): on the ComfyUI it
# trains on (this one, or the training host, its pod started first), puts
# its set in the inputs and queues the training graph, then checks back
# until ComfyUI has saved the LoRA, the run fails, or it times out
# (ApplicationJob#poll_comfy), waiting out a ComfyUI that can't be reached
# as a batch does.
class TrainingJob < ApplicationJob
  discard_on ActiveJob::DeserializationError # the run was deleted
  waits_for_services do |job, error|
    job.arguments.first.fail!("#{error.message}. Tried for a day; train it again once it's back.")
  end

  def perform(training, client: nil)
    client ||= begin
      training.client
    rescue Comfy::Error => e # no training host to talk to (TRAINING_COMFY_URL gone)
      return training.fail!(e.message)
    end
    poll_comfy(training, client) do
      training.start_host!
      training.submit!(client)
    end
  end
end
