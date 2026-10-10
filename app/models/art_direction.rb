# frozen_string_literal: true

# Helpers for composing a recipe in layers (docs/HANDOFF.md "The layered
# recipe"): the project's house style, the kind's framing, the entry's look,
# what a derived subject's parents say, the subject's specifics, a variant's
# detail.
module ArtDirection
  module_function

  OFF = [ false, "0", "false", "off" ].freeze

  # [{ "name", "strength", "on" }] from form rows or JSON: blank names
  # dropped, strength a float (default 1.0) kept within ComfyUI's usual
  # range, on unless switched off.
  def loras(value)
    rows = value.is_a?(Hash) ? value.values : Array(value)
    rows.filter_map do |row|
      row = row.to_h.stringify_keys
      name = row["name"].to_s.strip
      next if name.empty?

      strength = row["strength"].to_s.strip.empty? ? 1.0 : row["strength"].to_f
      { "name" => name, "strength" => strength.clamp(-5.0, 5.0).round(2), "on" => !OFF.include?(row.fetch("on", true)) }
    end
  end

  # The LoRAs stacked in layer order, project first. A LoRA a later layer
  # names again keeps its place in the stack and takes the later layer's
  # strength and switch: that is how a subject turns a project LoRA down or off.
  # Every LoRA is kept, on or off, so the pages can show what was switched off.
  def stack_loras(*layers)
    layers.flat_map { |layer| loras(layer) }
          .each_with_object({}) { |lora, by_name| by_name[lora["name"]] = lora }
          .values
  end

  def active_loras(stack)
    stack.select { |lora| lora["on"] && !lora["strength"].zero? }
  end

  # The model from the lowest layer that names one: subject, then kind, then
  # project, then the configured default.
  def pick_model(*layers_bottom_up)
    layers_bottom_up.map { |model| model.to_s.strip }.find { |model| !model.empty? }
  end

  # The prompt from a recipe's parts, in layer order. (Recipes made before
  # entries have no "entry" part, and before derived kinds no "parent".)
  def compose(parts)
    join_prompt(*parts.values_at("prefix", "style", "framing", "entry", "parent", "subject", "detail"))
  end

  def join_prompt(*parts)
    parts.map { |part| part.to_s.strip.delete_suffix(",").strip }.reject(&:empty?).join(", ")
  end
end
