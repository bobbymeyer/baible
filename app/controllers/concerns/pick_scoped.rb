# frozen_string_literal: true

# Loads a pick in the URL (pick_id), with its file.
module PickScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_pick
  end

  private

  def set_pick
    @pick = Pick.find(params[:pick_id])
    head :not_found unless @pick.file.attached?
  end
end
