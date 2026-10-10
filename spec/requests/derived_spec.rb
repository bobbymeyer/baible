# frozen_string_literal: true

require "rails_helper"

# Deriving subjects in the studio, and laying out a design sheet
# (docs/HANDOFF.md "Derived kinds and sheets").
RSpec.describe "Derived subjects and sheets", type: :request do
  include ActiveJob::TestHelper

  let(:project) { make_project }
  let(:cid) { make_subject(project, "Character", "Cid", notes: "white beard") }
  let(:comfy) { FakeComfy.new }

  before { allow(Comfy).to receive(:client).and_return(comfy) }

  def pick_one(subject, **params)
    post subject_batches_path(subject), params: { count: 1, draft: "0", **params }
    post candidate_pick_path(finish(subject.batch_for(params[:variant_id] && subject.variants.find(params[:variant_id])), comfy).candidates.sole)
    subject.pick_for(nil)
  end

  it "derives subjects from a character in a click, each starting from its picture as its kind says" do
    get subject_path(cid)
    expect(page.at("#derived").text).to include("Character sprite", "Portrait", "Costume", "Character design sheet", "Make one of every kind")

    post subject_derivations_path(cid), params: { kind_id: project.kinds.find_by!(name: "Portrait").id }
    portrait = cid.derived_subjects.sole
    expect(response).to redirect_to(subject_path(portrait))
    expect(portrait).to have_attributes(name: "Cid", kind: project.kinds.find_by!(name: "Portrait"))

    post subject_derivations_path(cid), params: { kind_id: project.kinds.find_by!(name: "Portrait").id }
    expect(flash[:alert]).to include("Portrait already has a Cid")

    post subject_derivations_path(cid), params: { kind_id: "every" }
    expect(cid.derived_subjects.reload.map { |s| s.kind.name }).to contain_exactly("Character sprite", "Portrait", "Model sheet", "Costume", "Character design sheet")
    post subject_derivations_path(cid), params: { kind_id: "every" }
    expect(flash[:alert]).to include("has one of every kind")

    get subject_path(portrait)
    expect(page.at(".crumbs").text).to include("from Cid (Character)")
    expect(page.at("#from_pick_id option[selected]")["value"]).to eq("derived")
    expect(page.at("#generate").text).to include("Cid has no picture yet")

    drawn = pick_one(cid)
    post subject_batches_path(portrait), params: { count: 1, draft: "1", from_pick_id: "derived" }
    expect(portrait.batch_for.recipe).to include("source" => include("pick_id" => drawn.id, "crop" => "head"), "denoise" => 0.55)
    post subject_batches_path(portrait), params: { count: 1, from_pick_id: "derived", denoise: "0.3" }
    expect(portrait.batch_for.recipe["denoise"]).to eq(0.3)
    post subject_batches_path(portrait), params: { count: 1, from_pick_id: "" }
    expect(portrait.batch_for.recipe["source"]).to be_nil
  end

  it "adds a costume with its own name from the form, and a portrait of the costume" do
    get new_project_subject_path(project, parent_id: cid.id)
    expect(page.at("select[name='subject[parent_id]'] option[selected]").text).to eq("Cid")

    costume = project.kinds.find_by!(name: "Costume")
    post project_subjects_path(project), params: { subject: { name: "Cid, winter coat", kind_id: costume.id, parent_id: cid.id, notes: "fur-lined coat" } }
    coat = Subject.find_by!(name: "Cid, winter coat")
    expect(coat.parent).to eq(cid)

    post subject_derivations_path(coat), params: { kind_id: project.kinds.find_by!(name: "Portrait").id }
    expect(coat.derived_subjects.sole.recipe.dig("parts", "parent")).to eq("Cid, white beard, fur-lined coat")

    patch subject_path(coat), params: { subject: { parent_id: make_subject(project, "Creature", "Goblin").id } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(page.text).to include("Parent must be a Character")

    get project_path(project)
    expect(page.at("##{ActionView::RecordIdentifier.dom_id(costume)}").text).to include("from Character", "from Cid")
  end

  it "makes a derived kind and a sheet on the Kinds page" do
    character = project.kinds.find_by!(name: "Character")
    post project_kinds_path(project), params: { kind: { name: "Battle sprite", medium: "image", parent_id: character.id, derive: "picture", derive_denoise: "0.65" } }
    battle = project.kinds.find_by!(name: "Battle sprite")
    expect(battle).to have_attributes(parent: character, derived_start: { "crop" => nil, "denoise" => 0.65 })

    post project_kinds_path(project), params: { kind: { name: "Expression sheet", medium: "sheet", parent_id: character.id,
                                                        sheet_kind_ids: [ "", project.kinds.find_by!(name: "Portrait").id.to_s ] } }
    expression = project.kinds.find_by!(name: "Expression sheet")
    expect(expression.sheet_kinds.map(&:name)).to eq([ "Portrait" ])

    get project_kinds_path(project)
    expect(page.at("##{ActionView::RecordIdentifier.dom_id(battle)}").text).to include("Character: redraw its picture, re-noised 0.65")
    expect(page.at("##{ActionView::RecordIdentifier.dom_id(expression)}").text).to include("Lays out", "Portrait")
    get edit_project_kind_path(project, expression)
    expect(response).to have_http_status(:ok)

    delete project_kind_path(project, character)
    expect(flash[:alert]).to be_present
    expect(Kind.exists?(character.id)).to be(true)
  end

  it "lays out a design sheet in its studio, and picks it" do
    portrait = Subject.create!(project: project, kind: project.kinds.find_by!(name: "Portrait"), name: "Cid", parent: cid)
    pick_one(cid)
    pick_one(portrait)
    post subject_derivations_path(cid), params: { kind_id: project.kinds.find_by!(name: "Character design sheet").id }
    design = Subject.find_by!(kind: project.kinds.find_by!(name: "Character design sheet"))

    get subject_path(design)
    expect(page.at("#generate").text).to include("Character", "Portrait", "Lay out the sheet")
    expect(page.at("#variants")).to be_nil

    perform_enqueued_jobs { post subject_batches_path(design) }
    candidate = design.batch_for.candidates.sole
    expect(candidate.status).to eq("done")
    get subject_path(design)
    expect(page.at("#batches").text).to include("Cid: Character design sheet")

    post candidate_pick_path(candidate)
    get subject_path(design)
    expect(page.at("#picks").text).not_to include("Seed")
    get pick_sidecar_path(design.pick_for)
    expect(response.parsed_body).to include("medium" => "sheet")
  end
end
