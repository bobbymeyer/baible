# frozen_string_literal: true

# A ComfyUI graph the builder can't make (docs/HANDOFF.md "Unknown models
# and new workflows"): written by the language model (WorkflowWriter) from
# a person's description, in API form, with baible's placeholders where a
# batch's values go (Comfy::Template), checked node by node against the
# server's own definitions (Comfy::GraphCheck), tried, and accepted by a
# person. Accepted, a kind can make its pictures with it: the graph is
# frozen into each batch's recipe, so a picture can always be made again.
class LearnedWorkflow < ApplicationRecord
  include Learnable

  has_many :kinds, dependent: :nullify

  validates :name, presence: true, uniqueness: true
  validates :purpose, presence: true

  def placeholders = Comfy::Template.placeholders(graph)

  def check(definitions) = Comfy::GraphCheck.errors(graph, definitions)

  # A test render with a plain prompt and the default model, checked
  # against the server as a batch would be.
  def trial_graph(prompt:, seed:, prefix:, client:, capabilities:)
    values = { "prompt" => prompt, "negative" => "", "seed" => seed, "width" => 1024, "height" => 1024, "prefix" => prefix,
               "model" => Comfy.config[:model] }
    raise Comfy::Error, "A test render can't start from a picture: try it from a kind's studio" if placeholders.include?("{{source_image}}")

    filled = Comfy::Template.fill(graph, values)
    problems = Comfy::GraphCheck.errors(filled, client.node_definitions(filled.values.map { |node| node["class_type"] }), template: false)
    raise Comfy::Error, problems.join("; ") if problems.any?

    filled
  end
end
