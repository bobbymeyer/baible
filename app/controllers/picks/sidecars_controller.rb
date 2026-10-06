# frozen_string_literal: true

# A pick's sidecar: how its file was made, as JSON beside it
# (Pick#sidecar, docs/HANDOFF.md "Export").
class Picks::SidecarsController < ApplicationController
  include PickScoped

  def show
    send_data JSON.pretty_generate(@pick.sidecar), filename: @pick.sidecar_filename, type: :json,
                                                    disposition: params[:inline] ? "inline" : "attachment"
  end
end
