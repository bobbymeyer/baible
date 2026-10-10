# frozen_string_literal: true

# Workflows the language model writes from a description: asking (create,
# again for one of the same name), a person's edit of the graph (update:
# checked against the server, back to proposed), and deleting one (kinds
# using it go back to the builder's graph).
class LearnedWorkflowsController < ApplicationController
  def create
    name = params.require(:name).to_s.strip
    workflow = LearnedWorkflow.find_or_initialize_by(name: name)
    workflow.assign_attributes(purpose: params[:purpose].presence || workflow.purpose, user: workflow.user || Current.user,
                               status: "asking", error: nil, accepted_by: nil, accepted_at: nil)
    raise Refusal, "Say what the workflow should do" if workflow.purpose.blank?

    workflow.save!
    LearnJob.perform_later(workflow)
    redirect_to learning_path(anchor: helpers.dom_id(workflow)), notice: "Asking the language model to write #{name}.", status: :see_other
  end

  def update
    workflow = LearnedWorkflow.find(params[:id])
    graph = JSON.parse(params.require(:graph))
    raise Refusal, "The graph must be a JSON object" unless graph.is_a?(Hash)

    definitions = Comfy.client.node_definitions(graph.values.filter_map { |node| node["class_type"] if node.is_a?(Hash) })
    problems = Comfy::GraphCheck.errors(graph, definitions)
    raise Refusal, "Not saved: #{problems.first(6).join('; ')}" if problems.any?

    workflow.update!(graph: graph, outline: Comfy::Workflow.outline(graph), status: "proposed", error: nil, accepted_by: nil, accepted_at: nil)
    workflow.note!("Edited by #{Current.user&.email_address}: #{JSON.generate(graph)}")
    redirect_to learning_path(anchor: helpers.dom_id(workflow)), notice: "Saved. Try it again before accepting it.", status: :see_other
  rescue JSON::ParserError => e
    raise Refusal, "That isn't JSON: #{e.message.truncate(120)}"
  end

  def destroy
    workflow = LearnedWorkflow.find(params[:id])
    workflow.destroy!
    redirect_to learning_path, notice: "#{workflow.name} is gone.", status: :see_other
  end
end
