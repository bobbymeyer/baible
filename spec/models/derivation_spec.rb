# frozen_string_literal: true

require "rails_helper"

# Kinds derived from kinds, subjects from subjects, and sheets
# (docs/HANDOFF.md "Derived kinds and sheets").
RSpec.describe "Derived kinds and sheets" do
  include ActiveJob::TestHelper

  let(:project) { make_project(style: "ink wash") }
  let(:character) { project.kinds.find_by!(name: "Character") }
  let(:portrait) { project.kinds.find_by!(name: "Portrait") }
  let(:costume) { project.kinds.find_by!(name: "Costume") }
  let(:sheet) { project.kinds.find_by!(name: "Character design sheet") }
  let(:cid_entry) { project.entries.create!(name: "Cid", look: "eyepatch over the left eye") }
  let(:cid) { make_subject(project, "Character", "Cid", entry: cid_entry, notes: "white beard, red coat", loras: [ { "name" => "cid_v1" } ]) }

  def pick!(subject, variant: nil, seed: 7, canon: false)
    Pick.new(subject: subject, variant: variant, seed: seed, current: true, recipe: { "medium" => "image" }, canon_at: (Time.current if canon)).tap do |pick|
      pick.file.attach(io: StringIO.new(FakeComfy.png), filename: "#{subject.name.parameterize}-#{seed}.png", content_type: "image/png")
      pick.save!
    end
  end

  it "starts a project with a Character and kinds derived from it, and a design sheet of them" do
    expect(character.parent).to be_nil
    expect(character.derived_kinds.map(&:name)).to eq([ "Character sprite", "Portrait", "Model sheet", "Costume", "Character design sheet" ])
    expect(portrait).to have_attributes(derive: "head", derived_start: { "crop" => "head", "denoise" => 0.55 })
    expect(project.kinds.find_by!(name: "Model sheet").derived_start).to be_nil
    expect(sheet).to be_sheet
    expect(sheet.sheet_kinds.map(&:name)).to eq([ "Character", "Character sprite", "Portrait", "Model sheet", "Costume" ])
    expect(project.kinds.find_by!(name: "Creature").parent).to be_nil
  end

  it "keeps the kind tree sound" do
    expect(character.update(parent: portrait)).to be(false)
    expect(character.errors[:parent]).to include("can't be itself or derive from it")
    expect(project.kinds.create(name: "Loose sheet", medium: "sheet").errors[:parent]).to include(/is needed for a sheet/)
    expect(project.kinds.create(name: "Leitmotif", medium: "audio", parent: character).errors[:medium]).to include(/can't be audio/)
    expect(project.kinds.create(name: "Elsewhere", parent: make_project("Other").kinds.first).errors[:parent]).to include("must be one of the project's")
    expect(portrait.parent_kinds.map(&:name)).to eq([ "Character", "Character sprite", "Model sheet", "Costume" ])
  end

  it "puts the parent's words, LoRAs and entry before a derived subject's own" do
    cid_portrait = make_subject(project, "Portrait", "Cid", parent: cid, notes: "a faint smile")
    expect(cid_portrait.entry).to eq(cid_entry)

    recipe = cid_portrait.recipe
    expect(recipe["parts"]).to include("entry" => "eyepatch over the left eye", "parent" => "Cid, white beard, red coat", "subject" => "a faint smile")
    expect(recipe["positive"]).to end_with("eyepatch over the left eye, Cid, white beard, red coat, a faint smile")
    expect(recipe["loras"].map { |lora| lora["name"] }).to eq([ "cid_v1" ])
    expect(cid_portrait.layers.map { |layer| layer["role"] }).to eq(%w[Project Kind Entry Character Subject])

    # A costume of Cid, and a portrait of the costume: both parents' words, root first.
    coat = make_subject(project, "Costume", "Cid, winter coat", parent: cid, notes: "a heavy fur-lined coat")
    coat_portrait = make_subject(project, "Portrait", "Cid, winter coat", parent: coat)
    expect(coat_portrait.recipe.dig("parts", "parent")).to eq("Cid, white beard, red coat, a heavy fur-lined coat")
    expect(cid.descendants).to eq([ cid_portrait, coat, coat_portrait ])
    expect(cid.derivable_kinds.map(&:name)).to eq([ "Character sprite", "Portrait", "Model sheet", "Costume", "Character design sheet" ])

    # A model on the kind wins over the parent's; the parent's over the project's.
    cid.update!(model: "cid-model.safetensors")
    expect(cid_portrait.reload.model_file).to eq("cid-model.safetensors")
    portrait.update!(model: "portraits.safetensors")
    expect(cid_portrait.reload.model_file).to eq("portraits.safetensors")
  end

  it "refuses a parent its kind doesn't derive from, and a loop" do
    goblin = make_subject(project, "Creature", "Goblin")
    expect(project.subjects.create(kind: portrait, name: "Goblin", parent: goblin).errors[:parent]).to include("must be a Character (or derived from one)")
    expect(project.subjects.create(kind: project.kinds.find_by!(name: "Item"), name: "Knife", parent: cid).errors[:parent]).to include(/needs a kind derived/)

    coat = make_subject(project, "Costume", "Cid, winter coat", parent: cid)
    coat_portrait = make_subject(project, "Portrait", "Cid, winter coat", parent: coat)
    expect(coat.update(parent: coat_portrait)).to be(false)
    expect(coat.errors[:parent]).to include("can't be itself or derive from it")
  end

  it "starts a derived subject's batch from its parent's picture, a variant's from its own, as the kind says" do
    cid_portrait = make_subject(project, "Portrait", "Cid", parent: cid)
    words = Batch.start!(cid_portrait, count: 1, draft: true)
    expect(words.recipe["source"]).to be_nil # nothing of Cid's picked yet
    expect(words.draft?).to be(true)

    drawn = pick!(cid, seed: 42)
    batch = Batch.start!(cid_portrait, count: 2, draft: true)
    expect(batch.recipe).to include("source" => include("pick_id" => drawn.id, "crop" => "head"), "denoise" => 0.55)
    expect(batch.draft?).to be(false)
    expect(batch.candidates.first.seed).to eq(42)
    expect(Batch.start!(cid_portrait, count: 1, source: nil).recipe["source"]).to be_nil

    own = pick!(cid_portrait, seed: 9)
    happy = cid_portrait.variants.find_by!(name: "happy")
    expect(Batch.start!(cid_portrait, variant: happy, count: 1).recipe).to include("source" => include("pick_id" => own.id), "denoise" => 0.45)
    expect(Batch.start!(cid_portrait, variant: happy, count: 1).recipe.dig("source", "crop")).to be_nil

    turnaround = make_subject(project, "Model sheet", "Cid", parent: cid)
    expect(Batch.start!(turnaround, count: 1).recipe["source"]).to be_nil # words: a back view isn't redrawn from a front one
  end

  it "lays out a sheet of a character and what derives from it, picked like anything else" do
    cid_portrait = make_subject(project, "Portrait", "Cid", parent: cid)
    coat = make_subject(project, "Costume", "Cid, winter coat", parent: cid)
    pick!(cid, seed: 1)
    pick!(cid_portrait, seed: 2)
    pick!(cid_portrait, variant: cid_portrait.variants.find_by!(name: "happy"), seed: 3)
    make_subject(project, "Model sheet", "Cid", parent: cid) # nothing picked: left off
    pick!(coat, seed: 4)
    design = make_subject(project, "Character design sheet", "Cid", parent: cid)

    batch = Batch.start!(design, count: 4, tonight: true)
    expect(batch.recipe["sheet"]).to eq(
      "title" => "Cid: Character design sheet",
      "rows" => [
        { "label" => "Character", "subject_id" => cid.id, "cells" => [ { "pick_id" => cid.pick_for.id, "label" => "Character" } ] },
        { "label" => "Portrait", "subject_id" => cid_portrait.id,
          "cells" => [ { "pick_id" => cid_portrait.pick_for.id, "label" => "Portrait" },
                       { "pick_id" => cid_portrait.pick_for(cid_portrait.variants.find_by!(name: "happy")).id, "label" => "happy" } ] },
        { "label" => "Costume: Cid, winter coat", "subject_id" => coat.id, "cells" => [ { "pick_id" => coat.pick_for.id, "label" => "Costume" } ] }
      ]
    )
    expect(batch).to have_attributes(night: false, status: "queued")
    expect(batch.candidates.size).to eq(1)

    comfy = FakeComfy.new
    BatchJob.new.perform(batch, client: comfy)
    expect(comfy.submitted).to be_empty
    candidate = batch.reload.candidates.sole
    expect(candidate).to have_attributes(status: "done")
    expect(batch.status).to eq("done")
    image = Vips::Image.new_from_buffer(candidate.file.download, "")
    expect([ image.width, image.height ]).to eq([ batch.recipe["width"], batch.recipe["height"] ])
    expect(image.height).to be > 3 * Sheet::CELL

    pick = candidate.pick!
    expect(pick.sidecar).to include("medium" => "sheet", "kind" => "Character design sheet", "entry" => "Cid")
    expect(pick.sidecar.dig("recipe", "sheet", "rows").size).to eq(3)
    expect(cid_entry.pick_rows.map(&:first)).not_to include(design) # never in a training set
  end

  it "fails a sheet whose picture went, and refuses one with nothing to lay out" do
    design = make_subject(project, "Character design sheet", "Cid", parent: cid)
    expect { Batch.start!(design) }.to raise_error(Refusal, /Nothing to lay out yet/)

    gone = pick!(cid)
    batch = Batch.start!(design)
    gone.destroy!
    BatchJob.new.perform(batch)
    expect(batch.reload).to have_attributes(status: "failed", error: include("A picture on the sheet (Character) is gone"))
  end

  it "leaves sheets out of what standing orders make" do
    make_subject(project, "Character design sheet", "Cid", parent: cid)
    order = project.standing_orders.create!(action: "fill_gaps", nightly_limit: 50)
    expect(order.targets.map(&:first).map(&:kind).map(&:name)).not_to include("Character design sheet")
  end
end
