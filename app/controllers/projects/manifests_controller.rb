# frozen_string_literal: true

# Every current pick in a project, as one JSON document (docs/HANDOFF.md
# "Export"): each pick's sidecar with where to download its file and
# sidecar. No archive: fetch the files it lists.
class Projects::ManifestsController < ApplicationController
  include ProjectScoped

  def show
    picks = @project.picks.includes(:variant, subject: :kind, file_attachment: :blob).order(:subject_id, :variant_id)
    manifest = {
      "baible" => Pick::SIDECAR_VERSION,
      "project" => @project.name,
      "exported_at" => Time.current.utc.iso8601,
      "picks" => picks.select { |pick| pick.file.attached? }.map do |pick|
        pick.sidecar.merge("download_url" => pick_download_url(pick), "sidecar_url" => pick_sidecar_url(pick))
      end
    }
    send_data JSON.pretty_generate(manifest), type: :json, disposition: params[:inline] ? "inline" : "attachment",
                                              filename: "#{@project.name.parameterize}-manifest.json"
  end
end
