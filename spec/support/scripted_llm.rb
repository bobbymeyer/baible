# frozen_string_literal: true

# Stands in for Llm::Client: answers each ask with the next scripted reply
# (text, read as a model's reply would be), and keeps what it was asked.
class ScriptedLlm
  attr_reader :asked

  def initialize(*replies)
    @replies = replies
    @asked = []
  end

  def chat(system:, user:, **)
    @asked << { system: system, user: user }
    reply = @replies.shift
    reply.is_a?(Exception) ? raise(reply) : reply
  end

  def json(system:, user:, **)
    Llm.parse_json(chat(system: system, user: user)) || raise(Llm::Error, "The language model didn't answer in JSON")
  end
end
