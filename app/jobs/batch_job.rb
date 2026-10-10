# frozen_string_literal: true

# Drives a Batch (docs/HANDOFF.md "Batches, candidates, picks"): lays out a
# sheet's, or submits its
# candidates to ComfyUI, then checks back every few seconds and collects
# each file as it lands, until all are in, the batch fails, or it times out
# (ApplicationJob#poll_comfy).
#
# When ComfyUI or the language model can't be reached at all (asleep,
# restarting, off the network), nothing is lost: the batch says it's
# waiting, and the job is tried again (ApplicationJob.waits_for_services).
# ComfyUI answering with an error (a missing model, a bad graph) still fails
# the batch, with its reason.
class BatchJob < ApplicationJob
  discard_on ActiveJob::DeserializationError # the batch was discarded or replaced
  waits_for_services do |job, error|
    job.arguments.first.fail!("#{error.message}. Tried for a day; start it again once it's back.")
  end

  def perform(batch, client: Comfy.client, llm: Llm.enabled? ? Llm.client : nil)
    return batch.compose_sheet! if batch.sheet? # laid out here: no ComfyUI

    poll_comfy(batch, client) do
      batch.write_prompt!(llm) if llm
      batch.upload_source!(client)
      batch.submit!(client)
    end
  end
end
