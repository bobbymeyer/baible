# frozen_string_literal: true

# What one ComfyUI server can do, read from its /object_info: which nodes it
# has, and the files and choices each loader and sampler offers. The graph is
# built against this, so it only asks for what is really there, whatever
# machine ComfyUI is on and however its models are laid out.
module Comfy
  class Capabilities
    # The nodes the builder may use, the background-removal node
    # (ComfyUI-RMBG's, Cutout), and ACE-Step's for audio (Comfy::Music).
    NODES = %W[CheckpointLoaderSimple UNETLoader CLIPLoader VAELoader LoraLoader LoraLoaderModelOnly
               CLIPSetLastLayer CLIPTextEncode ConditioningZeroOut KSampler EmptyLatentImage EmptySD3LatentImage
               VAEDecode SaveImage LoadImage ImageScale VAEEncode #{Cutout::NODE}
               EmptyAceStepLatentAudio TextEncodeAceStepAudio ModelSamplingSD3 VAEDecodeAudio SaveAudio SaveAudioMP3].freeze

    # offline: nothing answered at all (Comfy::Unreachable), rather than
    # ComfyUI answering with an error.
    def self.unreachable(error = nil, offline: false) = new({}, reachable: false, error: error, offline: offline)

    # info: { node class => its /object_info definition }
    def initialize(info, reachable: true, error: nil, offline: false)
      @info = info.to_h
      @reachable = reachable
      @error = error
      @offline = offline
    end

    def reachable? = @reachable
    def offline? = @offline

    # Why it isn't, when it isn't.
    attr_reader :error

    # How ComfyUI describes a node, or nil.
    def info(name) = @info[name.to_s]

    def node?(name) = @info.key?(name.to_s)

    # The choices for one of a node's inputs. ComfyUI has written these two
    # ways: [[choices...], {...}] and ["COMBO", { "options" => [choices...] }].
    def options(node, input)
      spec = @info.dig(node, "input", "required", input) || @info.dig(node, "input", "optional", input)
      return [] unless spec.is_a?(Array)

      spec.first.is_a?(Array) ? spec.first : Array(spec.dig(1, "options"))
    end

    def checkpoints = options("CheckpointLoaderSimple", "ckpt_name")
    def diffusion_models = options("UNETLoader", "unet_name")
    def text_encoders = options("CLIPLoader", "clip_name")
    def clip_types = options("CLIPLoader", "type")
    def vaes = options("VAELoader", "vae_name")
    def loras = options("LoraLoader", "lora_name").presence || options("LoraLoaderModelOnly", "lora_name")
    def samplers = options("KSampler", "sampler_name")
    def schedulers = options("KSampler", "scheduler")

    # Every model a layer could name, for the pickers.
    def models = (diffusion_models + checkpoints).uniq

    # A file as ComfyUI names it (with its subfolder), from a name that may
    # leave the subfolder off.
    def find(list, name)
      name = name.to_s
      list.find { |file| file == name } || list.find { |file| File.basename(file) == File.basename(name) }
    end

    def checkpoint?(name) = !find(checkpoints, name).nil?
    def diffusion_model?(name) = !find(diffusion_models, name).nil?

    # The first file whose name has one of the fragments in it, trying the
    # fragments in order.
    def find_like(list, fragments)
      fragments.each do |fragment|
        hit = list.find { |file| File.basename(file).downcase.include?(fragment.to_s.downcase) }
        return hit if hit
      end
      nil
    end

    # The first preference ComfyUI offers, or nil.
    def prefer(available, preferences)
      preferences.map(&:to_s).find { |choice| available.include?(choice) }
    end
  end
end
