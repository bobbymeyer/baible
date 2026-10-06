# frozen_string_literal: true

require "rails_helper"
require "vips"

# polychrome's chain (sprite → neutral portrait from its head → each
# expression from the neutral portrait), made from generic parts: a batch
# that starts from a pick, its head cut or not, re-noised.
RSpec.describe "Chains: starting a batch from a pick", type: :request do
  include ActiveJob::TestHelper

  let(:project) { make_project }
  let(:sprite) { make_subject(project, "Character sprite", "Cid", notes: "white beard, goggles") }
  let(:portrait) { make_subject(project, "Portrait", "Cid", notes: "white beard, goggles") }
  let(:comfy) { FakeComfy.new }

  # A real figure for the head to be cut from: a body with a head on top, on a transparent canvas.
  def figure_png
    canvas = Vips::Image.black(200, 400, bands: 4)
    body = Vips::Image.black(60, 200, bands: 4).new_from_image([ 200, 40, 40, 255 ])
    head = Vips::Image.black(40, 40, bands: 4).new_from_image([ 240, 200, 180, 255 ])
    canvas.insert(body, 70, 180).insert(head, 80, 140).write_to_buffer(".png")
  end

  def node(graph, type) = graph.values.find { |n| n["class_type"] == type }

  it "draws the sprite, the portrait from its head, then every expression from the portrait" do
    # 1. The sprite, from the prompt.
    post subject_batches_path(sprite), params: { count: 1, draft: "0" }
    batch = finish(sprite.batch_for(nil), comfy)
    batch.candidates.sole.file.attach(io: StringIO.new(figure_png), filename: "cid.png", content_type: "image/png")
    post candidate_pick_path(batch.candidates.sole)
    sprite_pick = sprite.pick_for(nil)

    get subject_path(portrait)
    expect(page.at("select#from_pick_id optgroup[label='Cid (Character sprite)'] option")["value"]).to eq(sprite_pick.id.to_s)

    # 2. The portrait from the sprite's head, with the sprite's seed.
    post subject_batches_path(portrait), params: { count: 2, draft: "1", from_pick_id: sprite_pick.id, crop: "head" }
    batch = portrait.batch_for(nil)
    expect(batch).not_to be_draft # starting from a pick, never a draft
    expect(batch.recipe).to include("source" => { "pick_id" => sprite_pick.id, "crop" => "head", "label" => "Cid" }, "denoise" => 0.55)
    expect(batch.candidates.first.seed).to eq(sprite_pick.seed)
    finish(batch, comfy)
    expect(comfy.uploads.map(&:first)).to eq([ "baible-head-#{sprite_pick.id}-#{sprite_pick.seed}.png" ])
    head = Vips::Image.new_from_buffer(comfy.uploads.first.last, "")
    expect([ head.width, head.height ]).to eq([ 82, 82 ]) # a third of the figure's height, square
    expect(batch.reload.recipe["workflow"]).to include("LoadImage", "VAEEncode")
    expect(node(comfy.submitted.last, "KSampler")["inputs"]["denoise"]).to eq(0.55)
    get subject_path(portrait)
    expect(response.body).to include("Candidates for Cid, from the head of Cid")
    post candidate_pick_path(batch.candidates.last)
    neutral = portrait.pick_for(nil)

    # 3. Every expression, each from the portrait, the whole picture this time.
    post subject_batches_path(portrait), params: { every: "1", count: 1, from_pick_id: neutral.id, denoise: "0.4" }
    strips = portrait.batches.reload.to_a
    expect(strips.map { |b| b.variant.name }).to match_array(portrait.variants.map(&:name))
    expect(strips.map { |b| b.recipe["source"] }.uniq).to eq([ { "pick_id" => neutral.id, "label" => "Cid" } ])
    expect(strips.map { |b| b.recipe["denoise"] }.uniq).to eq([ 0.4 ])
    expect(strips.map { |b| b.candidates.first.seed }.uniq).to eq([ neutral.seed ])
    angry = strips.find { |b| b.variant.name == "angry" }
    expect(angry.recipe["positive"]).to end_with("angry expression, furrowed brow")
    finish(angry, comfy)
    expect(comfy.uploads.last.first).to eq("baible-from-#{neutral.id}-#{neutral.seed}.png")
    expect(comfy.uploads.last.last).to eq(neutral.file.download)

    # The sidecar says where it came from.
    post candidate_pick_path(angry.candidates.sole)
    expect(portrait.pick_for(portrait.variants.find_by!(name: "angry")).sidecar["source"]).to eq("label" => "Cid", "denoise" => 0.4)
  end

  it "starts only from an image pick in the same project" do
    elsewhere = make_project("Elsewhere")
    other = make_subject(elsewhere, "Creature", "Wolf")
    post subject_batches_path(other), params: { count: 1, draft: "0" }
    finish(other.batch_for(nil), comfy)
    post candidate_pick_path(other.batch_for(nil).candidates.sole)

    post subject_batches_path(portrait), params: { from_pick_id: other.pick_for(nil).id }
    expect(response).to have_http_status(:not_found)
    expect(portrait.batches).to be_empty
  end

  it "fails the batch, saying so, when the picture it starts from is gone" do
    post subject_batches_path(sprite), params: { count: 1, draft: "0" }
    post candidate_pick_path(finish(sprite.batch_for(nil), comfy).candidates.sole)
    post subject_batches_path(portrait), params: { count: 1, from_pick_id: sprite.pick_for(nil).id }
    sprite.pick_for(nil).destroy!
    batch = finish(portrait.batch_for(nil), comfy)
    expect(batch).to have_attributes(status: "failed", error: "The picture to draw from (Cid) is gone")
  end
end
