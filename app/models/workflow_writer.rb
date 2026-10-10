# frozen_string_literal: true

# Asks the language model for a ComfyUI graph the builder can't make
# (docs/HANDOFF.md "Unknown models and new workflows"), from a person's
# description, in two steps: which of the server's nodes it needs (from the
# names of all of them), then the graph, given those nodes' own definitions
# and a graph the builder makes as an example. Each graph is checked node
# by node against the server (Comfy::GraphCheck); a failing one is sent back
# with its problems, up to ATTEMPTS times. The result is a proposal, never
# used until a person tries and accepts it.
module WorkflowWriter
  ATTEMPTS = 3
  MAX_NODES = 30

  PLACEHOLDER_RULES = <<~TEXT.squish
    Where a batch's values go, use these strings exactly as the input's value: "{{prompt}}" and "{{negative}}" (text),
    "{{seed}}", "{{width}}", "{{height}}" (whole numbers), "{{model}}" (the image model's file, in a loader's file choice),
    "{{source_image}}" (a picture to start from, in LoadImage's image), and "{{prefix}}" as the filename_prefix of the SaveImage
    node that saves the result. Every other value must be a literal the node accepts, or a link [node id, output index].
  TEXT

  module_function

  def propose!(workflow, client:, llm:)
    info = client.object_info
    raise Comfy::Error, "ComfyUI listed no nodes" if info.blank?

    example = example_graph(client)
    nodes = choose_nodes(workflow, info, example, llm)
    definitions = info.slice(*(nodes + example.values.map { |node| node["class_type"] }).uniq)
    user = graph_request(workflow, definitions, example)
    ATTEMPTS.times do |attempt|
      answer = llm.json(system: graph_system, user: user, temperature: 0.2, max_tokens: 4000)
      graph = answer.to_h["graph"].is_a?(Hash) ? answer["graph"] : answer.to_h
      graph = graph.transform_keys(&:to_s)
      problems = Comfy::GraphCheck.errors(graph, info)
      workflow.note!("Attempt #{attempt + 1}: #{JSON.generate(graph)}#{"\nProblems: #{problems.join('; ')}" if problems.any?}")
      if problems.empty?
        return workflow.update!(status: "proposed", graph: graph, outline: Comfy::Workflow.outline(graph), error: nil)
      end

      user = "#{graph_request(workflow, definitions, example)}\n\nYour last graph had these problems; answer again with the whole graph:\n- #{problems.join("\n- ")}"
    end
    workflow.update!(status: "failed", error: "The language model's #{ATTEMPTS} graphs didn't pass the server's checks: see the log.")
  end

  # The nodes it asks for, of those the server has.
  def choose_nodes(workflow, info, example, llm)
    system = "You choose ComfyUI nodes for a workflow. Reply with one JSON object and nothing else: " \
             "{\"nodes\": [node class names]}, at most #{MAX_NODES}, only names from the list given."
    user = <<~TEXT
      The workflow should: #{workflow.purpose}
      A graph this server already runs, for an ordinary picture: #{JSON.generate(example)}
      Every node on this server: #{info.keys.sort.join(', ')}
    TEXT
    chosen = Array(llm.json(system: system, user: user, temperature: 0.2, max_tokens: 800).to_h["nodes"]).map(&:to_s)
    workflow.note!("Nodes asked for: #{chosen.join(', ')}")
    (chosen & info.keys).first(MAX_NODES)
  end

  def graph_system
    "You write ComfyUI workflows in API format. Reply with one JSON object and nothing else: {\"graph\": {node id: " \
      "{\"class_type\": ..., \"inputs\": {...}}}}. Use only the nodes defined below, only their inputs, and give every required " \
      "input. #{PLACEHOLDER_RULES}"
  end

  def graph_request(workflow, definitions, example)
    <<~TEXT
      The workflow should: #{workflow.purpose}
      An example of a graph that runs on this server, with the placeholders in place: #{JSON.generate(example)}
      The nodes you may use, as the server defines them (inputs: name => type or choices; outputs in order):
      #{definitions.map { |name, definition| "#{name}: #{JSON.generate(compact(definition))}" }.join("\n")}
    TEXT
  end

  # A definition cut down to what writing a graph needs: long choice lists
  # are shortened.
  def compact(definition)
    inputs = %w[required optional].to_h do |kind|
      [ kind, definition.dig("input", kind).to_h.transform_values do |spec|
        Comfy::GraphCheck.combo?(spec) ? Comfy::GraphCheck.choices(spec).first(20) : spec
      end ]
    end
    { "inputs" => inputs, "outputs" => Array(definition["output"]) }
  end

  # The builder's own graph for an ordinary picture, with the placeholders
  # in place, or {} when the default model isn't on the server.
  def example_graph(client)
    caps = client.capabilities
    model = Comfy.config[:model]
    graph = Comfy::Workflow.build({ "model" => model, "loras" => [], "positive" => "{{prompt}}", "negative" => "{{negative}}",
                                    "width" => 1024, "height" => 1024 }, seed: 0, prefix: "{{prefix}}", capabilities: caps)
    graph.each_value do |node|
      inputs = node["inputs"]
      inputs["seed"] = "{{seed}}" if inputs.key?("seed")
      %w[width height].each { |side| inputs[side] = "{{#{side}}}" if inputs.key?(side) && node["class_type"].start_with?("Empty") }
      %w[unet_name ckpt_name].each { |key| inputs[key] = "{{model}}" if inputs[key] == caps.find(caps.diffusion_models + caps.checkpoints, model) }
    end
    graph
  rescue Comfy::Error
    {}
  end
end
