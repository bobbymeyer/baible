# frozen_string_literal: true

# The pick that stands for each target in a project (its canon, or its
# current pick), as one JSON document (docs/HANDOFF.md "Export"): each
# pick's sidecar with where to download its file and sidecar, and the
# targets with nothing picked yet (a skeleton's placeholders, with their
# refs). No archive: fetch the files it lists.
class Projects::ManifestsController < ApplicationController
  include ProjectScoped

  def show
    picks = Pick.standing(@project.picks.includes(:variant, :user, :canon_by, subject: %i[kind entry], file_attachment: :blob)
                                        .order(:subject_id, :variant_id))
    manifest = {
      "baible" => Pick::SIDECAR_VERSION,
      "project" => @project.name,
      "exported_at" => Time.current.utc.iso8601,
      "picks" => picks.select { |pick| pick.file.attached? }.map do |pick|
        pick.sidecar.merge("download_url" => pick_download_url(pick), "sidecar_url" => pick_sidecar_url(pick))
      end,
      "missing" => missing(picks)
    }
    send_data JSON.pretty_generate(manifest), type: :json, disposition: params[:inline] ? "inline" : "attachment",
                                              filename: "#{@project.name.parameterize}-manifest.json"
  end

  private

  def missing(picks)
    picked = picks.to_set { |pick| [ pick.subject_id, pick.variant_id ] }
    @project.subjects.includes(:kind, :entry, :variants).sort_by { |subject| [ subject.kind.position, subject.name.downcase ] }.flat_map do |subject|
      [ nil, *subject.variants ].reject { |variant| picked.include?([ subject.id, variant&.id ]) }.map do |variant|
        { "ref" => variant ? variant.ref : subject.ref, "subject_ref" => subject.ref, "kind" => subject.kind.name,
          "entry" => subject.entry&.name, "subject" => subject.name, "variant" => variant&.name }
      end
    end
  end
end
