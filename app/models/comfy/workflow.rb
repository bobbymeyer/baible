# frozen_string_literal: true

# Builds the ComfyUI workflow (API format) for one image, from its recipe,
# the model's family and what the server has installed. Nothing is
# templated: each graph has only the nodes this image needs.
#
# - The model loads the way its file is stored: a checkpoint in one node, a
#   bare diffusion model with its text encoder and VAE found beside it.
# - LoRAs chain in the recipe's order, patching the model alone unless the
#   family's LoRAs train the text encoder too. Switched-off LoRAs aren't there.
# - CLIP skip only when the family wants it.
# - No negative encode when the sampler would ignore it (cfg 1): the empty
#   conditioning is made from the positive one instead.
# - Sampler and scheduler are the family's first preference the server has.
# - A reference (a pick to draw from in a new pose): the picture goes in
#   through IP-Adapter, patching the model, and the sampler starts from an
#   empty latent, so the prompt sets the pose and the picture the design.
#   Otherwise a source image is a start, encoded and re-noised in part.
# - Background removal when asked for: the picture as rendered is saved
#   ("-plain"), then put through the removal node (Cutout.wire) and saved
#   again, cut out. A ComfyUI without the node can't make it.
#
# Raises Comfy::Error, saying what's missing, when the server can't make it.
module Comfy
  module Workflow
    module_function

    # recipe: "model", "family", "loras" [{ "name", "strength", "on" }],
    #         "positive", "negative", "width", "height", "transparent"
    def build(recipe, seed:, prefix:, capabilities:)
      caps = capabilities
      model_name = recipe["model"] || recipe["checkpoint"]
      family = Family.new(recipe["family"].presence || Family.for(model_name, capabilities: caps).slug, model_name)
      graph = {}
      add = adder(graph)
      need = ->(node) { caps.node?(node) or raise Error, "ComfyUI has no #{node} node" }

      model, clip, vae = load(add, model_name, family, caps)

      active_loras(recipe).each do |lora|
        name = caps.find(caps.loras, lora["name"]) or raise Error, "The LoRA #{lora['name']} isn't on ComfyUI (models/loras)"
        strength = lora["strength"].to_f
        if family.lora_clip? && caps.node?("LoraLoader")
          loader = add.("LoraLoader", { "lora_name" => name, "strength_model" => strength, "strength_clip" => strength,
                                        "model" => model, "clip" => clip })
          model = [ loader, 0 ]
          clip = [ loader, 1 ]
        else
          need.("LoraLoaderModelOnly")
          model = [ add.("LoraLoaderModelOnly", { "lora_name" => name, "strength_model" => strength, "model" => model }), 0 ]
        end
      end

      reference = recipe["source_image"] && recipe.dig("source", "use") == "reference"
      model = ipadapter(add, model, recipe, family, caps) if reference

      clip = [ add.("CLIPSetLastLayer", { "stop_at_clip_layer" => -family.clip_skip, "clip" => clip }), 0 ] if family.clip_skip > 1

      positive = [ add.("CLIPTextEncode", { "text" => recipe["positive"].to_s, "clip" => clip }), 0 ]
      negative = if family.negative?
        [ add.("CLIPTextEncode", { "text" => recipe["negative"].to_s, "clip" => clip }), 0 ]
      elsif caps.node?("ConditioningZeroOut")
        [ add.("ConditioningZeroOut", { "conditioning" => positive }), 0 ]
      else
        [ add.("CLIPTextEncode", { "text" => "", "clip" => clip }), 0 ]
      end

      # A draft keeps its small size; anything else is scaled into range.
      width, height = recipe["draft"] ? [ recipe.fetch("width").to_i, recipe.fetch("height").to_i ] : family.size(recipe.fetch("width").to_i, recipe.fetch("height").to_i)
      denoise = 1
      if recipe["source_image"] && !reference
        # A start: the chosen draft or pick, scaled, encoded, and re-noised in part.
        %w[LoadImage ImageScale VAEEncode].each { |node| need.(node) }
        loaded = add.("LoadImage", { "image" => recipe["source_image"] })
        scaled = add.("ImageScale", { "image" => [ loaded, 0 ], "upscale_method" => "lanczos", "width" => width, "height" => height, "crop" => "disabled" })
        latent = add.("VAEEncode", { "pixels" => [ scaled, 0 ], "vae" => vae })
        denoise = recipe["denoise"] || family.refine_denoise
      else
        latent_node = caps.node?(family.latent) ? family.latent : "EmptyLatentImage"
        latent = add.(latent_node, { "width" => width, "height" => height, "batch_size" => 1 })
      end
      sampler = add.("KSampler", {
        "seed" => seed, "steps" => recipe["steps"] || family.steps, "cfg" => family.cfg,
        "sampler_name" => caps.prefer(caps.samplers, family.samplers) || caps.samplers.first || "euler",
        "scheduler" => caps.prefer(caps.schedulers, family.schedulers) || caps.schedulers.first || "normal",
        "denoise" => denoise, "model" => model, "positive" => positive, "negative" => negative, "latent_image" => [ latent, 0 ]
      })
      image = [ add.("VAEDecode", { "samples" => [ sampler, 0 ], "vae" => vae }), 0 ]

      if recipe["transparent"]
        # The picture as rendered too, to put back what the removal takes
        # from inside the subject (Cutout.keep_interior).
        add.("SaveImage", { "filename_prefix" => "#{prefix}#{Cutout::PLAIN}", "images" => image })
        image = Cutout.wire(add, image, caps)
      end

      add.("SaveImage", { "filename_prefix" => prefix, "images" => image })
      graph
    end

    # The model, patched by IP-Adapter to draw from the recipe's source
    # image (the uploaded pick), at the recipe's weight: the family's own
    # IP-Adapter and CLIP vision files when the server has both
    # (IPAdapterModelLoader, CLIPVisionLoader, IPAdapterAdvanced: an
    # Illustrious one), else ComfyUI_IPAdapter_plus's unified loader, whose
    # preset finds the models, and its IPAdapter node. Other inputs keep the
    # defaults the server reports, so a newer version of the nodes still fits.
    def ipadapter(add, model, recipe, family, caps)
      unless family.reference == "ipadapter"
        raise Error, "Drawing from a reference is built for SDXL and SD 1.5 models (IP-Adapter), and #{family.label} isn't one: " \
                     "start from its words instead, or redraw the picture"
      end
      settings = Comfy.config.fetch(:reference, {}).to_h.stringify_keys
      weight = (recipe["reference_weight"] || settings["weight"] || 0.8).to_f
      own = family_ipadapter(add, family, caps)
      if own
        ipadapter, clip_vision = own
        image = add.("LoadImage", { "image" => recipe["source_image"] })
        inputs = node_defaults(caps, "IPAdapterAdvanced").merge(
          "model" => model, "ipadapter" => [ ipadapter, 0 ], "clip_vision" => [ clip_vision, 0 ], "image" => [ image, 0 ], "weight" => weight
        )
        return [ add.("IPAdapterAdvanced", inputs), 0 ]
      end

      %w[IPAdapterUnifiedLoader IPAdapter LoadImage].each do |node|
        next if caps.node?(node)

        raise Error, "ComfyUI has no #{node} node: install ComfyUI_IPAdapter_plus (by cubiq) in the Manager, with its SDXL models, to draw from a reference"
      end
      preset = caps.prefer(caps.options("IPAdapterUnifiedLoader", "preset"), Array(settings["presets"])) ||
               caps.options("IPAdapterUnifiedLoader", "preset").first || Array(settings["presets"]).first
      loader = add.("IPAdapterUnifiedLoader", { "model" => model, "preset" => preset })
      image = add.("LoadImage", { "image" => recipe["source_image"] })
      inputs = node_defaults(caps, "IPAdapter").merge(
        "model" => [ loader, 0 ], "ipadapter" => [ loader, 1 ], "image" => [ image, 0 ],
        "weight" => weight
      )
      [ add.("IPAdapter", inputs), 0 ]
    end

    # The family's own IP-Adapter and CLIP vision model, loaded by file, as
    # [ipadapter node, clip vision node]; nil when it names none or the
    # server lacks the files or the nodes (the unified loader is used).
    def family_ipadapter(add, family, caps)
      return if family.ipadapter_files.empty?
      return unless %w[IPAdapterModelLoader CLIPVisionLoader IPAdapterAdvanced LoadImage].all? { |node| caps.node?(node) }

      file = caps.find_like(caps.ipadapters, family.ipadapter_files) or return
      vision = caps.find_like(caps.clip_visions, family.clip_visions) or return
      [ add.("IPAdapterModelLoader", { "ipadapter_file" => file }), add.("CLIPVisionLoader", { "clip_name" => vision }) ]
    end

    # A node's required inputs as the server describes them: each default,
    # or a choice's first option. Links and inputs without either are left out.
    def node_defaults(caps, node)
      caps.defaults(node).filter_map do |input, default|
        value = default.nil? ? caps.options(node, input).first : default
        [ input, value ] unless value.nil?
      end.to_h
    end

    # A graph to add nodes to: add.(class_type, inputs) gives the new node's id.
    def adder(graph)
      lambda do |class_type, inputs|
        (graph.size + 1).to_s.tap { |id| graph[id] = { "class_type" => class_type, "inputs" => inputs } }
      end
    end

    # The model, its text encoder and its VAE, loaded the way the model's
    # file is stored, as [model, clip, vae], each [node id, output]: a bare
    # diffusion model with its family's text encoder and VAE found beside it,
    # or a checkpoint with its own (or the family's VAE in its place).
    # Training loads it the same way (Comfy::Training).
    def load(add, model_name, family, caps)
      need = ->(node) { caps.node?(node) or raise Error, "ComfyUI has no #{node} node" }
      if (file = caps.find(caps.diffusion_models, model_name))
        need.("UNETLoader")
        model = [ add.("UNETLoader", { "unet_name" => file, "weight_dtype" => "default" }), 0 ]
        encoder = caps.find_like(caps.text_encoders, family.text_encoders) or
          raise Error, "#{family.label} needs its text encoder in models/text_encoders (a file like #{family.text_encoders.first || '?'})"
        type = caps.prefer(caps.clip_types, family.clip_types) or
          raise Error, "This ComfyUI's CLIPLoader has no #{family.clip_types.join(' or ')} type: update ComfyUI"
        clip = [ add.("CLIPLoader", { "clip_name" => encoder, "type" => type }), 0 ]
        vae_file = caps.find_like(caps.vaes, family.vaes) or
          raise Error, "#{family.label} needs its VAE in models/vae (a file like #{family.vaes.first || '?'})"
        vae = [ add.("VAELoader", { "vae_name" => vae_file }), 0 ]
      elsif (file = caps.find(caps.checkpoints, model_name))
        checkpoint = add.("CheckpointLoaderSimple", { "ckpt_name" => file })
        model = [ checkpoint, 0 ]
        clip = [ checkpoint, 1 ]
        override = caps.find_like(caps.vaes, family.vae_overrides)
        vae = override ? [ add.("VAELoader", { "vae_name" => override }), 0 ] : [ checkpoint, 2 ]
      else
        raise Error, "#{model_name} isn't on ComfyUI (looked in models/diffusion_models and models/checkpoints)"
      end
      [ model, clip, vae ]
    end

    # The LoRAs that take part: switched on, with some strength.
    def active_loras(recipe)
      Array(recipe["loras"]).select { |lora| lora.fetch("on", true) && !lora["strength"].to_f.zero? }
    end

    # The graph as a line of node names, for the pages ("UNETLoader →
    # CLIPLoader → ..."), repeats counted.
    def outline(graph)
      graph.values.map { |node| node["class_type"] }.chunk_while { |a, b| a == b }
           .map { |run| run.size > 1 ? "#{run.first} ×#{run.size}" : run.first }.join(" → ")
    end
  end
end
