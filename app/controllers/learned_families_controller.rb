# frozen_string_literal: true

# Families the language model writes for models config/comfy.yml doesn't
# know: asking (create, again for one that exists), a person's edit of the
# settings (update: checked against the server, back to proposed), and
# deleting one.
class LearnedFamiliesController < ApplicationController
  def create
    model = params.require(:model).to_s
    family = LearnedFamily.find_by(model: model) || LearnedFamily.for_model!(model, user: Current.user)
    family.update!(status: "asking", error: nil, accepted_by: nil, accepted_at: nil)
    LearnJob.perform_later(family)
    redirect_to learning_path(anchor: helpers.dom_id(family)), notice: "Asking the language model how to run #{model}.", status: :see_other
  end

  def update
    family = LearnedFamily.find(params[:id])
    settings = JSON.parse(params.require(:settings))
    raise Refusal, "The settings must be a JSON object" unless settings.is_a?(Hash)

    problems = Comfy::FamilyCheck.errors(settings, model: family.model, capabilities: Comfy.capabilities)
    raise Refusal, "Not saved: #{problems.join('; ')}" if problems.any?

    family.update!(settings: settings.slice(*LearnedFamily::KEYS), label: params[:label].presence || family.label,
                   status: "proposed", error: nil, accepted_by: nil, accepted_at: nil)
    family.note!("Edited by #{Current.user&.email_address}: #{JSON.generate(family.settings)}")
    redirect_to learning_path(anchor: helpers.dom_id(family)), notice: "Saved. Try it again before accepting it.", status: :see_other
  rescue JSON::ParserError => e
    raise Refusal, "That isn't JSON: #{e.message.truncate(120)}"
  end

  def destroy
    family = LearnedFamily.find(params[:id])
    family.destroy!
    redirect_to learning_path, notice: "#{family.label} is gone; #{family.model} runs as it did before.", status: :see_other
  end
end
