# frozen_string_literal: true

# Whether a ComfyUI graph in API form will run on a server, checked against
# that server's own definitions of its nodes (/object_info) before anything
# is queued (docs/HANDOFF.md "Unknown models and new workflows"): every node
# class exists, every input is one the node takes, a link points at a node
# in the graph and an output it has, of the type the input wants, a literal
# is of the input's type and in its range or list, every required input is
# given, and something saves the picture under {{prefix}}. A graph may hold
# baible's placeholders (Template) where a value of their type belongs.
# Returns the problems, in words the language model can act on.
module Comfy
  module GraphCheck
    module_function

    # definitions: { class_type => its /object_info definition }
    def errors(graph, definitions, template: true)
      return [ "the graph must be a JSON object of node id => { class_type, inputs }" ] unless graph.is_a?(Hash) && graph.any?

      problems = []
      graph.each do |id, node|
        unless node.is_a?(Hash) && node["class_type"].is_a?(String) && node["inputs"].is_a?(Hash)
          problems << "node #{id}: must have a class_type and an inputs object"
          next
        end
        type = node["class_type"]
        definition = definitions[type]
        unless definition
          problems << "node #{id}: there is no #{type} node on this ComfyUI"
          next
        end
        required = definition.dig("input", "required").to_h
        optional = definition.dig("input", "optional").to_h
        node["inputs"].each do |name, value|
          spec = required[name] || optional[name]
          next problems << "node #{id} (#{type}): it has no input called #{name}" unless spec

          problem = value_problem(value, spec, graph, definitions, template)
          problems << "node #{id} (#{type}) input #{name}: #{problem}" if problem
        end
        (required.keys - node["inputs"].keys).each { |name| problems << "node #{id} (#{type}): the required input #{name} is missing" }
      end
      if template && graph.values.none? { |node| node.is_a?(Hash) && node["class_type"] == "SaveImage" && node.dig("inputs", "filename_prefix") == "{{prefix}}" }
        problems << "nothing saves the picture: a SaveImage node needs filename_prefix \"{{prefix}}\""
      end
      problems
    end

    def value_problem(value, spec, graph, definitions, template)
      kind = spec_type(spec)
      if link?(value)
        source = graph[value[0].to_s] or return "links to node #{value[0]}, which isn't in the graph"
        outputs = Array(definitions.dig(source["class_type"], "output"))
        given = outputs[value[1]] or return "links to output #{value[1]} of node #{value[0]}, which has #{outputs.size}"
        return nil if kind == "*" || given == "*" || given.to_s.split(",").include?(kind) || kind.to_s.split(",").include?(given)

        return "takes #{kind}, but output #{value[1]} of node #{value[0]} gives #{given}"
      end
      if template && value.is_a?(String) && (placeholder = Template::PLACEHOLDERS[value])
        return nil if placeholder == kind || (placeholder == "COMBO" && combo?(spec))

        return "#{value} is #{placeholder.downcase}, but this input takes #{kind.to_s.downcase}"
      end
      if combo?(spec)
        options = choices(spec)
        return nil if options.include?(value)

        return "#{value.inspect} isn't one of its choices (#{options.first(12).map(&:to_s).join(', ')}#{', ...' if options.size > 12})"
      end
      limits = spec[1].is_a?(Hash) ? spec[1] : {}
      case kind
      when "INT"
        return "must be a whole number" unless value.is_a?(Integer)
      when "FLOAT"
        return "must be a number" unless value.is_a?(Numeric)
      when "STRING"
        return "must be text" unless value.is_a?(String)
      when "BOOLEAN"
        return "must be true or false" unless [ true, false ].include?(value)
      else
        return "takes a #{kind}, which only a link to another node can give"
      end
      return "must be at least #{limits['min']}" if limits["min"] && value.is_a?(Numeric) && value < limits["min"]
      return "must be at most #{limits['max']}" if limits["max"] && value.is_a?(Numeric) && value > limits["max"]

      nil
    end

    def link?(value) = value.is_a?(Array) && value.size == 2 && (value[0].is_a?(String) || value[0].is_a?(Integer)) && value[1].is_a?(Integer)

    def combo?(spec) = spec.is_a?(Array) && (spec[0].is_a?(Array) || spec[0] == "COMBO")

    def choices(spec) = spec[0].is_a?(Array) ? spec[0] : Array(spec.dig(1, "options"))

    def spec_type(spec)
      return "COMBO" if combo?(spec)

      spec.is_a?(Array) ? spec[0].to_s : spec.to_s
    end
  end
end
