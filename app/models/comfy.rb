# frozen_string_literal: true

# Talking to ComfyUI (docs/HANDOFF.md). Settings live in config/comfy.yml.
module Comfy
  class Error < StandardError; end
  # ComfyUI couldn't be reached at all (down, asleep, off the network), as
  # opposed to answering and refusing: worth trying again later (Remote).
  class Unreachable < Error; include Remote::Unreachable; end

  # The settings: config/comfy.yml (from the environment), with what
  # someone set on the Settings page (SiteSetting) taking precedence.
  def self.config
    overrides = SiteSetting.current.comfy_overrides
    overrides.empty? ? Rails.configuration.x.comfy : Rails.configuration.x.comfy.merge(overrides)
  end

  # The backend the pipeline talks to (see Comfy::Client for its interface).
  def self.client(timeout: 30)
    Client.new(timeout: timeout)
  end

  # What ComfyUI has installed, for the pickers and the workflow preview.
  # Remembered for a minute when ComfyUI answers; when it doesn't, only for
  # a few seconds, so starting it shows up on the next reload.
  def self.capabilities
    @capabilities = nil if @capabilities && @capabilities_at < (@capabilities.reachable? ? 1.minute : 5.seconds).ago
    @capabilities = nil if @capabilities_url && @capabilities_url != config[:url] # moved to another server
    @capabilities_url = config[:url]
    @capabilities ||= client(timeout: 3).capabilities.tap { @capabilities_at = Time.current }
  end

  def self.forget_capabilities!
    @capabilities = nil
  end
end
