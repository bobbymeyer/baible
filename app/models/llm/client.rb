# frozen_string_literal: true

# A language model over the network, through the OpenAI-compatible
# /chat/completions call that llama.cpp, llama-swap, Ollama, LM Studio, vLLM
# and hosted APIs all answer. Nothing here assumes which one.
#
# The interface the app uses; anything answering it can stand in:
#   chat(system:, user:) → the reply's text
#   json(system:, user:) → the reply parsed as a JSON object
module Llm
  class Client
    def initialize(url: Llm.config[:url], model: Llm.config[:model], token: Llm.config[:token],
                   headers: Llm.config[:headers], timeout: Llm.config[:timeout], extra_body: Llm.config[:extra_body], http: nil)
      @model = model.to_s
      @extra_body = Llm.extra_body(extra_body)
      @remote = Remote::Connection.new(service: Llm, name: "The language model", url: url, token: token, headers: headers,
                                       headers_setting: "LLM_HEADERS", timeout: timeout.to_i.positive? ? timeout.to_i : 120,
                                       open_timeout: 10, rejection: method(:rejection), http: http)
    end

    # A reply that is JSON, parsed. Local models wrap it in prose or code
    # fences often enough that the first object in the reply is taken; if
    # there's none, they're asked once more, plainly.
    def json(system:, user:, temperature: 0.7, max_tokens: 1500)
      reply = chat(system: system, user: user, temperature: temperature, max_tokens: max_tokens)
      Llm.parse_json(reply) || Llm.parse_json(chat(system: system, temperature: temperature, max_tokens: max_tokens,
                                                   user: "#{user}\n\nReply with one JSON object and nothing else.")) ||
        raise(Error, "The language model didn't answer in JSON")
    end

    # One exchange. Reasoning models' <think> blocks are left out of the reply.
    def chat(system:, user:, temperature: 0.3, max_tokens: 400)
      payload = { messages: [ { role: "system", content: system }, { role: "user", content: user } ],
                  temperature: temperature, max_tokens: max_tokens, stream: false }
      payload[:model] = @model if @model.present?
      payload = @extra_body.merge(payload.stringify_keys)
      body = @remote.json(@remote.post_json("/chat/completions", payload))
      text = body.dig("choices", 0, "message", "content").to_s
      text = text.gsub(%r{<think>.*?</think>}m, "").strip
      raise Error, "The language model sent an empty reply" if text.empty?

      text
    end

    private

    def rejection(response)
      detail = (JSON.parse(response.body.to_s).dig("error", "message") rescue nil)
      [ "The language model answered #{response.code}", detail ].compact.join(": ")
    end
  end
end
