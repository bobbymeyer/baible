# frozen_string_literal: true

# A run's set as a .tar, in the kohya layout, for a trainer elsewhere.
class Trainings::SetsController < ApplicationController
  include TrainingScoped

  def show
    send_data @training.tar, type: "application/x-tar", disposition: "attachment", filename: "#{@training.stem}.tar"
  rescue Comfy::Error => e
    raise Refusal, e.message
  end
end
