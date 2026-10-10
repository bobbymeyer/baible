# frozen_string_literal: true

require "zlib"

# Stands in for Comfy::Client in specs: records the graphs it is sent and
# answers from a script. `finish!` marks prompts done; `fail!` makes one error.
# It has Anima installed (and whatever else `capabilities` is given).
class FakeComfy
  attr_reader :submitted, :capabilities

  def initialize(capabilities: FakeComfy.capabilities)
    @capabilities = capabilities
    @submitted = []
    @done = []
    @failed = {}
  end

  def submit(graph)
    @submitted << graph
    "prompt-#{@submitted.size}"
  end

  def finish!(*ids) = @done.concat(ids)
  def fail!(id, message) = @failed[id] = message

  def result(id)
    raise Comfy::Error, @failed[id] if @failed.key?(id)
    return nil unless @done.include?(id)

    # One image for each SaveImage in the graph: the picture as rendered
    # ("-plain") and the cut-out, when the background comes off.
    graph = @submitted[id.delete_prefix("prompt-").to_i - 1] || {}
    # A graph that saves audio (Comfy::Music) gets one file back.
    audio = graph.values.find { |node| node["class_type"].to_s.start_with?("SaveAudio") }
    return [ { "filename" => "#{File.basename(audio.dig('inputs', 'filename_prefix').to_s)}_00001_.#{audio['class_type'] == 'SaveAudioMP3' ? 'mp3' : 'flac'}", "subfolder" => "baible", "type" => "output" } ] if audio

    saves = graph.values.select { |node| node["class_type"] == "SaveImage" }.map { |node| node.dig("inputs", "filename_prefix").to_s }
    saves = [ id ] if saves.empty?
    saves.map { |prefix| { "filename" => "#{File.basename(prefix)}_00001_.png", "subfolder" => "baible", "type" => "output" } }
  end

  # The picture as rendered is opaque; anything else comes back cut out,
  # unless told the removal left it opaque (cut: :opaque).
  attr_writer :cut

  def fetch(image)
    image["filename"].to_s.include?("#{Cutout::PLAIN}_") || @cut == :opaque ? FakeComfy.rgb_png : FakeComfy.png
  end

  def run_seconds(id) = (42.5 if @done.include?(id))

  # Node definitions as /object_info gives them, for learned workflows: a
  # spec gives its own, or gets a small set.
  attr_writer :definitions

  def definitions = @definitions ||= FakeComfy.definitions

  def node_definitions(names) = definitions.slice(*names)

  def object_info = definitions

  def self.definitions
    {
      "CheckpointLoaderSimple" => { "input" => { "required" => { "ckpt_name" => [ [ "sdxl.safetensors" ] ] } }, "output" => %w[MODEL CLIP VAE] },
      "CLIPTextEncode" => { "input" => { "required" => { "text" => [ "STRING", { "multiline" => true } ], "clip" => [ "CLIP" ] } }, "output" => %w[CONDITIONING] },
      "EmptyLatentImage" => { "input" => { "required" => { "width" => [ "INT", { "min" => 16, "max" => 8192 } ], "height" => [ "INT", { "min" => 16, "max" => 8192 } ],
                                                           "batch_size" => [ "INT", { "min" => 1, "max" => 64 } ] } }, "output" => %w[LATENT] },
      "KSampler" => { "input" => { "required" => { "model" => [ "MODEL" ], "seed" => [ "INT", { "min" => 0 } ], "steps" => [ "INT", { "min" => 1, "max" => 10_000 } ],
                                                   "cfg" => [ "FLOAT", { "min" => 0.0, "max" => 100.0 } ], "sampler_name" => [ %w[euler dpmpp_2m] ],
                                                   "scheduler" => [ %w[normal karras] ], "positive" => [ "CONDITIONING" ], "negative" => [ "CONDITIONING" ],
                                                   "latent_image" => [ "LATENT" ], "denoise" => [ "FLOAT", { "min" => 0.0, "max" => 1.0 } ] } }, "output" => %w[LATENT] },
      "VAEDecode" => { "input" => { "required" => { "samples" => [ "LATENT" ], "vae" => [ "VAE" ] } }, "output" => %w[IMAGE] },
      "SaveImage" => { "input" => { "required" => { "images" => [ "IMAGE" ], "filename_prefix" => [ "STRING", { "default" => "ComfyUI" } ] } }, "output" => [] },
      "ControlNetLoader" => { "input" => { "required" => { "control_net_name" => [ [ "openpose_sdxl.safetensors" ] ] } }, "output" => %w[CONTROL_NET] }
    }
  end

  # Prompts ComfyUI has from elsewhere (queue_size), as set by a spec.
  attr_writer :queue_size

  def queue_size = @queue_size.to_i

  def upload(bytes, name, subfolder: nil, content_type: "image/png")
    (@uploads ||= []) << [ [ subfolder, name ].compact.join("/"), bytes ]
    [ subfolder, name ].compact.join("/")
  end

  # LoRAs ComfyUI lists from now on (a training run's, once saved).
  def add_lora(name)
    @capabilities = FakeComfy.capabilities(loras: @capabilities.loras + [ name ])
  end

  def uploads = @uploads || []

  # A ComfyUI's /object_info, reduced to what the builder reads.
  def self.capabilities(checkpoints: [], diffusion_models: [ "anima-preview.safetensors" ],
                        text_encoders: [ "qwen_3_06b_base.safetensors" ], clip_types: %w[stable_diffusion sdxl anima],
                        vaes: [ "qwen_image_vae.safetensors" ], loras: [ "goblin.safetensors", "house.safetensors" ],
                        samplers: %w[euler euler_ancestral er_sde dpmpp_2m], schedulers: %w[normal karras simple sgm_uniform],
                        nodes: Comfy::Capabilities::NODES, extra: {})
    combo = ->(choices) { [ choices ] }
    info = nodes.index_with { { "input" => { "required" => {} } } }
    set = ->(node, input, choices) { info[node]["input"]["required"][input] = combo.(choices) if info[node] }
    set.("CheckpointLoaderSimple", "ckpt_name", checkpoints)
    set.("UNETLoader", "unet_name", diffusion_models)
    set.("CLIPLoader", "clip_name", text_encoders)
    set.("CLIPLoader", "type", clip_types)
    set.("VAELoader", "vae_name", vaes)
    set.("LoraLoader", "lora_name", loras)
    set.("LoraLoaderModelOnly", "lora_name", loras)
    set.("KSampler", "sampler_name", samplers)
    set.("KSampler", "scheduler", schedulers)
    Comfy::Capabilities.new(info.merge(extra))
  end

  # A 1×1 PNG, built by hand so specs need no image library.
  def self.png
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    "\x89PNG\r\n\x1A\n".b +
      chunk.("IHDR", [ 1, 1, 8, 6, 0, 0, 0 ].pack("NNCCCCC")) +
      chunk.("IDAT", Zlib::Deflate.deflate("\x00\x11\x11\x11\xFF".b)) +
      chunk.("IEND", "")
  end

  # The same pixel with no alpha: a picture as rendered.
  def self.rgb_png
    chunk = ->(type, data) { [ data.bytesize ].pack("N") + type + data + [ Zlib.crc32(type + data) ].pack("N") }
    "\x89PNG\r\n\x1A\n".b +
      chunk.("IHDR", [ 1, 1, 8, 2, 0, 0, 0 ].pack("NNCCCCC")) +
      chunk.("IDAT", Zlib::Deflate.deflate("\x00\x11\x11\x11".b)) +
      chunk.("IEND", "")
  end
end

# Pages ask what ComfyUI has installed; in specs they get FakeComfy's
# answer instead of reaching for the network.
RSpec.configure do |config|
  config.before { allow(Comfy).to receive(:capabilities).and_return(FakeComfy.capabilities) if defined?(Comfy) }
end
