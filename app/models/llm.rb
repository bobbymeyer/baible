# frozen_string_literal: true

# An optional language model (config/llm.yml), reached over an
# OpenAI-compatible chat API. Used to write image prompts (PromptWriter);
# everything works without one.
module Llm
  class Error < StandardError; end
  # The model couldn't be reached at all: worth trying again later (Remote).
  class Unreachable < Error; include Remote::Unreachable; end

  # config/llm.yml (from the environment), with the Settings page's
  # address and model taking precedence (SiteSetting).
  def self.config
    overrides = SiteSetting.current.llm_overrides
    overrides.empty? ? Rails.configuration.x.llm : Rails.configuration.x.llm.merge(overrides)
  end

  def self.enabled?
    config[:url].present?
  end

  def self.client
    Client.new
  end

  # LLM_EXTRA_BODY as a hash: a JSON object, or nothing. Anything else is a
  # mistake to say out loud rather than a request quietly sent without it.
  def self.extra_body(value)
    return value.to_h.stringify_keys if value.is_a?(Hash)
    return {} if value.to_s.strip.empty?

    parsed = JSON.parse(value.to_s)
    raise Error, "LLM_EXTRA_BODY must be a JSON object" unless parsed.is_a?(Hash)

    parsed
  rescue JSON::ParserError
    raise Error, "LLM_EXTRA_BODY isn't valid JSON"
  end

  # The first JSON object in a reply, or nil: code fences and chatter
  # around it are ignored.
  def self.parse_json(text)
    text = text.to_s
    start = text.index("{") or return nil
    depth = 0
    in_string = false
    escaped = false
    text[start..].each_char.with_index do |char, i|
      if in_string
        if escaped then escaped = false
        elsif char == "\\" then escaped = true
        elsif char == '"' then in_string = false
        end
      elsif char == '"' then in_string = true
      elsif char == "{" then depth += 1
      elsif char == "}"
        depth -= 1
        return JSON.parse(text[start, i + 1]) if depth.zero?
      end
    end
    nil
  rescue JSON::ParserError
    nil
  end
end
