# frozen_string_literal: true

# A pick's file, to save (docs/HANDOFF.md "Export"): what goes into
# polychrome's upload field, or anywhere else.
class Picks::DownloadsController < ApplicationController
  include PickScoped

  def show
    send_data @pick.file.download, filename: @pick.filename, type: @pick.file.content_type, disposition: "attachment"
  end
end
