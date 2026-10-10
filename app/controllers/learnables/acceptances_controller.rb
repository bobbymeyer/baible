# frozen_string_literal: true

# A person accepting a learned family or workflow, after its test render:
# from then on baible uses it.
class Learnables::AcceptancesController < ApplicationController
  include LearnableScoped

  def create
    @learnable.accept!(Current.user)
    redirect_to learning_path(anchor: helpers.dom_id(@learnable)), notice: "Accepted: baible uses it from now on.", status: :see_other
  end
end
