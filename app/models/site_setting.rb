# frozen_string_literal: true

# The app's own settings, one row, set on the Settings page: where ComfyUI
# and the language model answer, and their default models (images, audio,
# and the background-removal model, in ComfyUI). Anything left blank falls
# back to the environment (config/comfy.yml, config/llm.yml). Only addresses and names live here: a token, a header
# or a password in a URL stays in the environment, never in the database.
class SiteSetting < ApplicationRecord
  URLS = %i[comfy_url llm_url].freeze
  TEXT = %i[comfy_url comfy_model music_model rmbg_model llm_url llm_model].freeze
  NUMBERS = %i[draft_size draft_steps draft_denoise candidates].freeze
  FIELDS = (TEXT + NUMBERS).freeze

  normalizes(*TEXT, with: ->(value) { value.to_s.strip.presence })

  validates :draft_size, numericality: { only_integer: true, in: 256..1024 }, allow_nil: true
  validates :draft_steps, numericality: { only_integer: true, in: 1..60 }, allow_nil: true
  validates :draft_denoise, numericality: { in: 0.1..1.0 }, allow_nil: true
  validates :candidates, numericality: { only_integer: true, in: 1..8 }, allow_nil: true
  validate :urls_are_plain_addresses

  after_commit { self.class.forget! }

  # The row, remembered for a few seconds so every page doesn't ask the
  # database (and other app processes pick up a change quickly).
  def self.current
    @current = nil if @current_at && @current_at < 5.seconds.ago
    @current ||= (first || new).tap { @current_at = Time.current }
  rescue ActiveRecord::StatementInvalid
    new # before the table exists (a fresh deploy mid-migration)
  end

  def self.forget!
    @current = nil
  end

  # The settings that override the environment's, for Comfy.config.
  def comfy_overrides
    draft = { pixels: draft_size && draft_size**2, steps: draft_steps, denoise: draft_denoise }.compact
    overrides = { url: comfy_url, model: comfy_model, candidates: candidates }.compact
    overrides[:music] = Rails.configuration.x.comfy.fetch(:music, {}).to_h.symbolize_keys.merge(model: music_model) if music_model
    draft.empty? ? overrides : overrides.merge(draft: Rails.configuration.x.comfy.fetch(:draft, {}).to_h.symbolize_keys.merge(draft))
  end

  def llm_overrides
    { url: llm_url, model: llm_model }.compact
  end

  private

  def urls_are_plain_addresses
    URLS.each do |field|
      value = self[field] or next
      uri = URI.parse(value) rescue nil
      if !uri.is_a?(URI::HTTP) || uri.host.blank?
        errors.add(field, "must be an http:// or https:// address")
      elsif uri.userinfo
        errors.add(field, "can't hold a user or password: put those in the environment (COMFY_URL or LLM_URL), which never goes in the database")
      end
    end
  end
end
