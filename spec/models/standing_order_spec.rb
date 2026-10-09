# frozen_string_literal: true

require "rails_helper"

RSpec.describe StandingOrder do
  include ActiveJob::TestHelper

  let(:project) { make_project }
  let(:opened) { 1.minute.ago }

  def picked(subject, variant: nil, canon: false)
    Pick.new(subject: subject, variant: variant, seed: rand(1000), current: true, recipe: { "parts" => { "framing" => "a portrait", "subject" => subject.name } },
             canon_at: (Time.current if canon)).tap do |pick|
      subject.picks.where(variant: variant, current: true).update_all(current: false)
      pick.file.attach(io: StringIO.new(FakeComfy.png), filename: "p.png", content_type: "image/png")
      pick.save!
    end
  end

  it "fills the gaps: a scheduled batch for each target with no pick, within its kind, once a night" do
    wolf = make_subject(project, "Creature", "Wolf")
    goblin = make_subject(project, "Creature", "Goblin")
    picked(goblin)
    make_subject(project, "Item", "Lantern") # another kind: not this order's
    order = project.standing_orders.create!(action: "fill_gaps", kind: project.kinds.find_by!(name: "Creature"), count: 3)

    expect(order.plan!(opened)).to eq("Queued 1 batch of 3.")
    batch = Batch.sole
    expect(batch).to have_attributes(subject: wolf, status: "scheduled", night: true)
    expect(batch.candidates.size).to eq(3)

    expect(order.plan!(opened)).to eq("Queued 1 batch of 3.") # the same night: not again
    expect(Batch.count).to eq(1)

    # The next night: the wolf still has an unreviewed night batch, so nothing new.
    expect(order.plan!(Time.current + 1.second)).to eq("Queued 0 batches of 3; 1 target still waiting for review of an earlier night's.")
  end

  it "keeps going until canon, and keeps to its nightly limit" do
    cid = make_subject(project, "Portrait", "Cid") # six expressions: seven targets
    cid.variants.each { |variant| picked(cid, variant: variant) }
    picked(cid, canon: true)
    order = project.standing_orders.create!(action: "until_canon", nightly_limit: 4, count: 2)

    expect(order.plan!(opened)).to eq("Queued 4 batches of 2; 2 more owed, over the nightly limit.")
    expect(Batch.where(variant_id: nil)).to be_empty # Cid himself has canon
  end

  it "trains an entry once it has enough canon pictures, and not again on the same ones" do
    entry = project.entries.create!(name: "Cid", trigger: "cidx")
    portrait = make_subject(project, "Portrait", "Cid", entry: entry)
    order = project.standing_orders.create!(action: "train", entry: entry, min_pictures: 3, model: "sdxl_base_1.0.safetensors")

    picked(portrait, canon: true)
    expect(order.plan!(opened)).to eq("Waiting for 3 canon pictures; Cid has 1.")

    portrait.variants.first(2).each { |variant| picked(portrait, variant: variant, canon: true) }
    expect(order.plan!(Time.current)).to eq("Queued Cid v1 on 3 canon pictures, after the night's generations.")
    run = entry.trainings.sole
    expect(run).to have_attributes(status: "scheduled", trigger: "cidx", model: "sdxl_base_1.0.safetensors")
    expect(run.items.first["caption"]).to eq("cidx, a portrait, Cid")

    expect(order.plan!(Time.current)).to eq("Cid v1 is still to train or training.")
    run.update!(status: "done")
    expect(order.plan!(Time.current)).to eq("Nothing new since Cid v1: the same 3 canon pictures.")
  end

  it "says when there's no model to train on, and needs an entry to train" do
    entry = project.entries.create!(name: "Cid")
    make_subject(project, "Portrait", "Cid", entry: entry).then { |subject| picked(subject, canon: true) }
    order = project.standing_orders.create!(action: "train", entry: entry, min_pictures: 1)
    expect(order.plan!(opened)).to eq("No base model to train on: set one on this order, or COMFY_TRAINING_MODEL.")
    expect(project.standing_orders.new(action: "train")).not_to be_valid
  end

  it "is planned by the night shift's first tick of the night, before anything is let go" do
    make_subject(project, "Creature", "Wolf")
    order = project.standing_orders.create!(action: "fill_gaps")
    expect(NightShift.tick!(client: FakeComfy.new, at: Time.utc(2026, 10, 10, 12, 0))).to eq(:closed)
    expect(order.reload.planned_at).to be_nil

    outcome = NightShift.tick!(client: FakeComfy.new, at: Time.utc(2026, 10, 10, 2, 0))
    expect(outcome).to be_a(Batch)
    expect(order.reload.report).to eq("Queued 1 batch of 4.")
  end
end
