# frozen_string_literal: true

module Comfy
  # A stored graph's placeholders, and filling them for one candidate.
  module Template
    # Each placeholder, and the kind of input it may stand in.
    PLACEHOLDERS = {
      "{{prompt}}" => "STRING", "{{negative}}" => "STRING", "{{prefix}}" => "STRING",
      "{{seed}}" => "INT", "{{width}}" => "INT", "{{height}}" => "INT",
      "{{model}}" => "COMBO", "{{source_image}}" => "COMBO"
    }.freeze

    module_function

    # The graph with each placeholder replaced by its value; values by the
    # placeholder's name without braces ("prompt" => "...", "seed" => 7).
    def fill(graph, values)
      graph.to_h do |id, node|
        inputs = node["inputs"].to_h do |name, value|
          key = value.is_a?(String) && PLACEHOLDERS.key?(value) ? value.delete("{}") : nil
          [ name, key ? values.fetch(key) { raise Error, "This workflow needs #{value}, which this batch doesn't have" } : value ]
        end
        [ id.to_s, node.merge("inputs" => inputs) ]
      end
    end

    def placeholders(graph)
      graph.values.flat_map { |node| node["inputs"].to_h.values }.select { |value| value.is_a?(String) && PLACEHOLDERS.key?(value) }.uniq
    end
  end
end
