# frozen_string_literal: true

# Asks the language model for a learned family or workflow (FamilyWriter,
# WorkflowWriter), once. The language model or ComfyUI not answering, or
# answering with an error, fails it with the reason; asking again is a
# person's choice.
class LearnJob < ApplicationJob
  discard_on ActiveJob::DeserializationError

  def perform(learnable, client: Comfy.client, llm: Llm.client)
    raise Llm::Error, "No language model is set (LLM_URL, or the Settings page)" unless Llm.enabled?

    writer = learnable.is_a?(LearnedFamily) ? FamilyWriter : WorkflowWriter
    writer.propose!(learnable, client: client, llm: llm)
  rescue Llm::Error, Comfy::Error => e
    learnable.update!(status: "failed", error: e.message.truncate(500))
  end
end
