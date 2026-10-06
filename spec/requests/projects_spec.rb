# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Projects, kinds and subjects", type: :request do
  it "needs signing in", :signed_out do
    get projects_path
    expect(response).to redirect_to(new_session_path)
    get root_path
    expect(response).to redirect_to(new_session_path)

    user = make_user("me@example.com")
    post session_path, params: { email_address: "me@example.com", password: "wrong" }
    expect(response).to redirect_to(new_session_path)
    sign_in_as(user)
    get root_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("me@example.com", "Projects")
  end

  it "starts a project with the usual kinds, or without them" do
    post projects_path, params: { project: { name: "The Drowned Coast", style: "ink wash", loras: { "0" => { "name" => "ink", "strength" => "0.8" } } } }
    project = Project.find_by!(name: "The Drowned Coast")
    expect(response).to redirect_to(project_path(project))
    expect(project.loras).to eq([ { "name" => "ink", "strength" => 0.8, "on" => true } ])
    expect(project.kinds.map(&:name)).to eq(Kind.starters.map { |k| k["name"] })

    post projects_path, params: { project: { name: "Bare" }, starter_kinds: "0" }
    expect(Project.find_by!(name: "Bare").kinds).to be_empty

    post projects_path, params: { project: { name: "" } }
    expect(response).to have_http_status(:unprocessable_content)

    get projects_path
    expect(response.body).to include("The Drowned Coast", "Bare")
    get project_path(project)
    expect(response.body).to include("Creature", "Portrait", "Music", "New subject")
  end

  it "edits the project and kind layers, and the recipe follows" do
    project = make_project
    goblin = make_subject(project, "Creature", "Goblin")
    creature = goblin.kind

    get edit_project_path(project)
    expect(response.body).to include("house style", "Sound")
    patch project_path(project), params: { project: { style: "ink wash", negative: "photo", model: "", sound: "folk" } }
    expect(project.reload).to have_attributes(style: "ink wash", sound: "folk", model: nil)

    get project_kinds_path(project)
    expect(response.body).to include("ink wash", "Creature", "Music")
    get edit_project_kind_path(project, creature)
    expect(response.body).to include("Framing", "Remove the background")
    patch project_kind_path(project, creature), params: { kind: {
      prompt: "profile view, full body", width: "768", height: "768", transparent: "0", model: "krea2_turbo_bf16.safetensors",
      loras: { "0" => { "name" => "sprites", "strength" => "" }, "1" => { "name" => "ink", "strength" => "0.9", "on" => "0" } },
      variant_presets: "hurt: wounded, bleeding\nangry: snarling"
    } }
    expect(response).to redirect_to(project_kinds_path(project, anchor: "kind_#{creature.id}"))
    expect(creature.reload).to have_attributes(
      prompt: "profile view, full body", width: 768, transparent: false, model: "krea2_turbo_bf16.safetensors",
      loras: [ { "name" => "sprites", "strength" => 1.0, "on" => true }, { "name" => "ink", "strength" => 0.9, "on" => false } ],
      variant_presets: [ { "name" => "hurt", "prompt" => "wounded, bleeding" }, { "name" => "angry", "prompt" => "snarling" } ]
    )
    recipe = goblin.reload.recipe
    expect(recipe["positive"]).to start_with("ink wash, profile view, full body, Goblin")
    expect(recipe).to include("model" => "krea2_turbo_bf16.safetensors", "family" => "krea2", "negative" => "")

    get edit_project_kind_path(project, creature)
    expect(response.body).to include("Krea 2 Turbo · 8 steps · CFG 1 · no negative prompt")

    patch project_kind_path(project, creature), params: { kind: { width: "10" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Width must be in 256..2048")
  end

  it "adds kinds of either medium, and keeps one with subjects" do
    project = make_project
    post project_kinds_path(project), params: { kind: { name: "Battle theme", medium: "audio", prompt: "fast, drums", seconds: "90" } }
    battle = project.kinds.find_by!(name: "Battle theme")
    expect(battle).to have_attributes(medium: "audio", seconds: 90)

    get new_project_kind_path(project, medium: "audio")
    expect(page.at("fieldset[data-show-for=image]")["disabled"]).to be_present # its fields don't submit
    expect(page.at("fieldset[data-show-for=audio]")["disabled"]).to be_nil

    make_subject(project, "Battle theme", "The boss")
    delete project_kind_path(project, battle)
    expect(flash[:alert]).to include("still has subjects")
    expect(battle.reload).to be_present

    other = project.kinds.find_by!(name: "Emblem")
    delete project_kind_path(project, other)
    expect(Kind.exists?(other.id)).to be(false)
  end

  it "adds, renames and deletes subjects, with their kind's variants" do
    project = make_project
    portrait = project.kinds.find_by!(name: "Portrait")
    get new_project_subject_path(project, kind_id: portrait.id)
    expect(page.at("select#subject_kind_id option[selected]")["value"]).to eq(portrait.id.to_s)

    post project_subjects_path(project), params: { subject: { name: "Cid", kind_id: portrait.id, notes: "white beard" } }
    cid = project.subjects.find_by!(name: "Cid")
    expect(response).to redirect_to(subject_path(cid))
    expect(cid.variants.size).to eq(6)

    post project_subjects_path(project), params: { subject: { name: "Cid", kind_id: portrait.id } }
    expect(response).to have_http_status(:unprocessable_content)

    sprite = project.kinds.find_by!(name: "Character sprite")
    patch subject_path(cid), params: { subject: { name: "Cid Highwind", kind_id: sprite.id } }
    expect(cid.reload).to have_attributes(name: "Cid Highwind", kind: sprite)

    other = make_project("Elsewhere")
    patch subject_path(cid), params: { subject: { kind_id: other.kinds.first.id } }
    expect(response).to have_http_status(:not_found)

    delete subject_path(cid)
    expect(Subject.exists?(cid.id)).to be(false)
    expect(Variant.where(subject_id: cid.id)).to be_empty
  end

  it "edits a subject's variants" do
    cid = make_subject(make_project, "Portrait", "Cid")
    post subject_variants_path(cid), params: { variant: { name: "winter", prompt: "fur coat, snow" } }
    winter = cid.variants.find_by!(name: "winter")
    expect(winter.prompt).to eq("fur coat, snow")
    patch subject_variant_path(cid, winter), params: { variant: { prompt: "fur coat" } }
    expect(winter.reload.prompt).to eq("fur coat")
    post subject_variants_path(cid), params: { variant: { name: "winter" } }
    expect(flash[:alert]).to include("Name has already been taken")
    delete subject_variant_path(cid, winter)
    expect(cid.variants.reload.map(&:name)).not_to include("winter")
  end

  it "deletes a project with everything in it" do
    project = make_project
    goblin = make_subject(project, "Creature", "Goblin")
    batch = Batch.start!(goblin, count: 1)
    delete project_path(project)
    expect(response).to redirect_to(projects_path)
    expect([ Project, Kind, Subject, Batch, Candidate ].map(&:count)).to all(eq(0))
    expect(Batch.exists?(batch.id)).to be(false)
  end
end
