# frozen_string_literal: true

require "rails_helper"

# What leaves baible (docs/HANDOFF.md "Export"): a pick's file, its sidecar,
# and a project's manifest of every current pick.
RSpec.describe "Exporting picks", type: :request do
  include ActiveJob::TestHelper

  let(:project) { make_project(style: "ink wash") }
  let(:cid) { make_subject(project, "Portrait", "Cid", notes: "white beard") }
  let(:comfy) { FakeComfy.new }

  def pick_one(subject, variant: nil)
    post subject_batches_path(subject), params: { count: 1, draft: "0", variant_id: variant&.id }
    post candidate_pick_path(finish(subject.batch_for(variant), comfy).candidates.sole)
    subject.pick_for(variant)
  end

  it "downloads a pick's file and its sidecar, which says exactly how it was made" do
    pick = pick_one(cid)

    get pick_download_path(pick)
    expect(response.media_type).to eq("image/png")
    expect(response.headers["Content-Disposition"]).to include("attachment", "cid-#{pick.seed}.png")
    expect(response.body.b).to eq(pick.file.download.b)

    get pick_sidecar_path(pick)
    expect(response.media_type).to eq("application/json")
    expect(response.headers["Content-Disposition"]).to include("attachment", "cid-#{pick.seed}.json")
    sidecar = JSON.parse(response.body)
    expect(sidecar.keys).to eq(%w[baible file content_type byte_size sha256 medium project kind entry subject variant picked_by canon canon_by canon_at seed prompt negative model family
                                  loras width height transparent lyrics seconds source workflow run_seconds picked_at recipe])
    expect(sidecar).to include(
      "baible" => 1, "file" => "cid-#{pick.seed}.png", "content_type" => "image/png", "medium" => "image",
      "sha256" => Digest::SHA256.hexdigest(pick.file.download), "byte_size" => pick.file.byte_size,
      "project" => "The Drowned Coast", "kind" => "Portrait", "entry" => nil, "subject" => "Cid", "variant" => nil,
      "picked_by" => @user.email_address, "canon" => false, "canon_by" => nil, "canon_at" => nil,
      "seed" => pick.seed, "model" => "anima-preview.safetensors", "family" => "anima", "loras" => [],
      "width" => 1024, "height" => 1024, "transparent" => false, "lyrics" => nil, "seconds" => nil, "source" => nil, "run_seconds" => 42.5
    )
    expect(sidecar["prompt"]).to eq("masterpiece, best quality, ink wash, a head and shoulders portrait, facing the viewer, centered, plain background, Cid, white beard")
    expect(sidecar["workflow"]).to start_with("UNETLoader → CLIPLoader")
    expect(sidecar["recipe"]).to eq(pick.recipe)
    expect(Time.iso8601(sidecar["picked_at"])).to be_within(1.second).of(pick.created_at)
  end

  it "lists every current pick in the project's manifest, with where to download each" do
    base = pick_one(cid)
    happy = pick_one(cid, variant: cid.variants.find_by!(name: "happy"))
    make_subject(project, "Creature", "Wolf") # nothing picked: not listed

    get project_manifest_path(project)
    expect(response.headers["Content-Disposition"]).to include("the-drowned-coast-manifest.json")
    manifest = JSON.parse(response.body)
    expect(manifest).to include("baible" => 1, "project" => "The Drowned Coast")
    expect(manifest["picks"].map { |p| [ p["subject"], p["variant"], p["seed"] ] }).to eq([ [ "Cid", nil, base.seed ], [ "Cid", "happy", happy.seed ] ])
    expect(manifest["picks"].first).to include("download_url" => "http://www.example.com/picks/#{base.id}/download",
                                               "sidecar_url" => "http://www.example.com/picks/#{base.id}/sidecar")
    get manifest["picks"].first["download_url"]
    expect(response.body.b).to eq(base.file.download.b)
  end

  it "keeps everything behind signing in", :signed_out do
    pick = Pick.new(subject: cid, seed: 1, recipe: {}).tap { |p| p.file.attach(io: StringIO.new(FakeComfy.png), filename: "x.png", content_type: "image/png") }
    pick.save!
    get pick_download_path(pick)
    expect(response).to redirect_to(new_session_path)
    get project_manifest_path(project)
    expect(response).to redirect_to(new_session_path)
  end
end
