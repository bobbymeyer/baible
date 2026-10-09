# frozen_string_literal: true

require "rails_helper"

# Picks are kept (docs/HANDOFF.md "Picks: history and canon"): a target has a
# history, one current pick and at most one canon pick, and what stands for
# it is canon, else current.
RSpec.describe "Pick history and canon", type: :request do
  include ActiveJob::TestHelper

  let(:project) { make_project }
  let(:cid) { make_subject(project, "Portrait", "Cid") }
  let(:comfy) { FakeComfy.new }

  def pick_one(variant: nil)
    post subject_batches_path(cid), params: { count: 1, draft: "0", variant_id: variant&.id }
    post candidate_pick_path(finish(cid.batch_for(variant), comfy).candidates.sole)
    cid.target_picks(variant).first
  end

  it "keeps every pick, and a pick from the history can be used again" do
    first = pick_one
    second = pick_one
    expect(cid.target_picks.map(&:id)).to eq([ second.id, first.id ])
    expect(first.reload).not_to be_current
    expect(cid.pick_for(nil)).to eq(second)

    get subject_path(cid)
    expect(page.at("#pick_subject .history summary").text).to eq("History (2)")
    expect(page.at("##{ActionView::RecordIdentifier.dom_id(first)}").text).to include("Use this again", @user.email_address)

    post pick_current_path(first)
    expect(cid.reload.pick_for(nil)).to eq(first)
    expect(second.reload).not_to be_current
  end

  it "holds canon against new picks until someone approves another, and says so" do
    first = pick_one
    post pick_canon_path(first)
    expect(first.reload).to have_attributes(canon?: true, canon_by: @user)

    second = pick_one
    expect(flash[:notice]).to include("Canon is still the one approved before")
    expect(second.reload).to be_current
    expect(cid.reload.pick_for(nil)).to eq(first) # canon stands
    get subject_path(cid)
    expect(page.at("#pick_subject figcaption").text).to include("Canon", "Seed #{first.seed}", "newer pick (seed #{second.seed}) waits")
    expect(page.at("#pick_subject").attr("class")).to include("is-canon")

    # The manifest and the chains offer what stands: canon.
    get project_manifest_path(project)
    expect(JSON.parse(response.body)["picks"].map { |p| [ p["seed"], p["canon"] ] }).to eq([ [ first.seed, true ] ])

    post pick_canon_path(second)
    expect(first.reload).not_to be_canon
    expect(cid.reload.pick_for(nil)).to eq(second)
    expect(second.reload.sidecar).to include("canon" => true, "canon_by" => @user.email_address, "picked_by" => @user.email_address)

    delete pick_canon_path(second)
    expect(second.reload).not_to be_canon
    expect(cid.reload.pick_for(nil)).to eq(second) # current, now nothing is canon
  end

  it "won't let canon go until it's unapproved" do
    pick = pick_one
    post pick_canon_path(pick)
    delete pick_path(pick)
    expect(flash[:alert]).to include("can't be let go: unapprove it first")
    expect(Pick.exists?(pick.id)).to be(true)
  end

  it "keeps a variant's history apart from the subject's" do
    happy = cid.variants.find_by!(name: "happy")
    own = pick_one
    smile = pick_one(variant: happy)
    expect(cid.target_picks.map(&:id)).to eq([ own.id ])
    expect(cid.target_picks(happy).map(&:id)).to eq([ smile.id ])
    expect([ own.reload, smile.reload ]).to all(be_current)
    expect(cid.picked_targets).to eq(2)
  end

  it "keeps the picks when the picker's account goes" do
    pick = pick_one
    post pick_canon_path(pick)
    @user.destroy!
    expect(pick.reload).to have_attributes(user: nil, canon_by: nil, canon?: true)
  end
end
