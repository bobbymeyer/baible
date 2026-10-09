# frozen_string_literal: true

require "rails_helper"

# The bible (docs/HANDOFF.md "Data model"): an entry is one thing in the
# world across every kind it's made in, with lore for people and a look for
# every image of it.
RSpec.describe "The bible: entries", type: :request do
  include ActiveJob::TestHelper

  let(:project) { make_project }
  let(:comfy) { FakeComfy.new }

  it "adds an entry, then makes it in several kinds, each subject carrying its look" do
    get project_entries_path(project)
    expect(response.body).to include("No entries yet")

    post project_entries_path(project), params: { entry: { name: "Cid", look: "eyepatch over the left eye, red wool coat",
                                                           lore: "The harbourmaster's son.\n\nLost his eye in the siege." } }
    cid = project.entries.find_by!(name: "Cid")
    expect(response).to redirect_to(entry_path(cid))

    get entry_path(cid)
    expect(response.body).to include("Lost his eye in the siege", "eyepatch over the left eye")
    portrait = project.kinds.find_by!(name: "Portrait")
    expect(response.body).to include(new_project_subject_path(project, kind_id: portrait.id, entry_id: cid.id).gsub("&", "&amp;"))

    get new_project_subject_path(project, kind_id: portrait.id, entry_id: cid.id)
    expect(page.at("input#subject_name")["value"]).to eq("Cid")
    expect(page.at("select#subject_entry_id option[selected]").text).to eq("Cid")

    post project_subjects_path(project), params: { subject: { name: "Cid", kind_id: portrait.id, entry_id: cid.id, notes: "soaked by rain" } }
    sprite_kind = project.kinds.find_by!(name: "Character sprite")
    post project_subjects_path(project), params: { subject: { name: "Cid", kind_id: sprite_kind.id, entry_id: cid.id } }
    expect(cid.subjects.map { |s| s.kind.name }).to contain_exactly("Portrait", "Character sprite")

    portrait_cid = cid.subjects.find_by!(kind: portrait)
    expect(portrait_cid.recipe["positive"]).to include("plain background, eyepatch over the left eye, red wool coat, Cid, soaked by rain")
    get subject_path(portrait_cid)
    expect(response.body).to include(entry_path(cid))

    # The pick shows on the entry's page and says which entry it is of.
    post subject_batches_path(portrait_cid), params: { count: 1, draft: "0" }
    post candidate_pick_path(finish(portrait_cid.batch_for(nil), comfy).candidates.sole)
    pick = portrait_cid.pick_for(nil)
    expect(pick.sidecar["entry"]).to eq("Cid")
    get entry_path(cid)
    expect(response.body).to include(pick_download_path(pick), "Character sprite")
    get project_entries_path(project)
    expect(response.body).to include("Cid", "Portrait · Character sprite")
  end

  it "edits an entry, refuses a duplicate name, and deletes it without its subjects" do
    cid = project.entries.create!(name: "Cid")
    project.entries.create!(name: "Mara")
    sprite = make_subject(project, "Character sprite", "Cid", entry: cid)

    patch entry_path(cid), params: { entry: { name: "Mara" } }
    expect(response).to have_http_status(:unprocessable_content)
    patch entry_path(cid), params: { entry: { look: "grey stubble", loras: { "0" => { "name" => "cid.safetensors", "strength" => "0.8" } } } }
    expect(cid.reload.look).to eq("grey stubble")
    expect(sprite.recipe["loras"]).to include({ "name" => "cid.safetensors", "strength" => 0.8, "on" => true })

    delete entry_path(cid)
    expect(response).to redirect_to(project_entries_path(project))
    expect(sprite.reload.entry).to be_nil
    expect(sprite.recipe["parts"]["entry"]).to eq("")
  end

  it "links and unlinks a subject from its edit page, only to the project's own entries" do
    cid = project.entries.create!(name: "Cid")
    other = Project.create!(name: "Elsewhere").entries.create!(name: "Cid")
    sprite = make_subject(project, "Character sprite", "Cid")

    patch subject_path(sprite), params: { subject: { entry_id: other.id } }
    expect(sprite.reload.entry).to be_nil
    patch subject_path(sprite), params: { subject: { entry_id: cid.id } }
    expect(sprite.reload.entry).to eq(cid)
    patch subject_path(sprite), params: { subject: { entry_id: "" } }
    expect(sprite.reload.entry).to be_nil
  end
end
