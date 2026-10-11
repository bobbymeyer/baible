# frozen_string_literal: true

require "rails_helper"

# Importing a skeleton on its page, and the refs coming back in what leaves
# baible (docs/HANDOFF.md "Import: skeletons", "Export").
RSpec.describe "Skeletons", type: :request do
  include ActiveJob::TestHelper

  let(:skeleton) do
    { "baible_skeleton" => 1, "project" => { "name" => "The Drowned Coast" },
      "assets" => [ { "ref" => "speaker/12", "kind" => "Portrait", "name" => "Cid", "variants" => [ { "name" => "happy", "ref" => "speaker/12/happy" } ] },
                    { "ref" => "bestiary/3", "kind" => "Creature", "name" => "Drowned sailor" } ] }
  end

  def upload(data)
    file = Tempfile.new([ "skeleton", ".json" ]).tap { |f| f.write(JSON.generate(data)) && f.rewind }
    Rack::Test::UploadedFile.new(file.path, "application/json")
  end

  it "imports an uploaded skeleton as placeholders, and gives the refs back in the sidecar and the manifest" do
    get projects_path
    expect(page.at("a[href='#{new_skeleton_path}']").text).to eq("Import a skeleton")
    get new_skeleton_path
    expect(page.text).to include("The format", "baible_skeleton")

    post skeletons_path, params: { file: upload(skeleton) }
    project = Project.find_by!(name: "The Drowned Coast")
    expect(response).to redirect_to(project_path(project))
    expect(flash[:notice]).to eq("Made The Drowned Coast; 2 new placeholders.")

    cid = project.subjects.find_by!(ref: "speaker/12")
    get subject_path(cid)
    expect(page.at(".crumbs").text).to include("speaker/12")

    comfy = FakeComfy.new
    allow(Comfy).to receive(:client).and_return(comfy)
    happy = cid.variants.find_by!(name: "happy")
    post subject_batches_path(cid), params: { count: 1, draft: "0", variant_id: happy.id }
    post candidate_pick_path(finish(cid.batch_for(happy), comfy).candidates.sole)
    get pick_sidecar_path(cid.pick_for(happy))
    expect(response.parsed_body).to include("ref" => "speaker/12/happy", "subject_ref" => "speaker/12", "variant" => "happy")

    get project_manifest_path(project)
    manifest = response.parsed_body
    expect(manifest["picks"].map { |pick| pick["ref"] }).to eq([ "speaker/12/happy" ])
    expect(manifest["missing"]).to include({ "ref" => "speaker/12", "subject_ref" => "speaker/12", "kind" => "Portrait", "entry" => nil, "subject" => "Cid", "variant" => nil },
                                           { "ref" => "bestiary/3", "subject_ref" => "bestiary/3", "kind" => "Creature", "entry" => nil, "subject" => "Drowned sailor", "variant" => nil })
    expect(manifest["missing"].map { |row| row["variant"] }).not_to include("happy")
  end

  it "imports pasted JSON into the project it's imported from, and shows every problem when it can't" do
    project = make_project("Elsewhere")
    get project_path(project)
    get new_skeleton_path(project_id: project.id)
    expect(page.at("select[name=project_id] option[selected]").text).to eq("Elsewhere")
    expect(page.text).to include("Download Elsewhere's own skeleton")

    post skeletons_path, params: { project_id: project.id, json: JSON.generate(skeleton) }
    expect(project.subjects.count).to eq(2)

    bad = skeleton.merge("assets" => [ { "kind" => "Spaceship", "name" => "Gull" }, { "kind" => "Portrait" } ])
    post skeletons_path, params: { json: JSON.generate(bad) }
    expect(response).to have_http_status(:unprocessable_content)
    expect(page.at(".form-errors").text).to include("Nothing was imported", "no kind called \"Spaceship\"", "assets[1] (): a name is needed")

    post skeletons_path, params: { json: "" }
    expect(page.at(".form-errors").text).to include("Choose a file, or paste the JSON")
  end

  it "downloads a project's own skeleton, and lets a subject's ref be edited" do
    project = make_project
    cid = make_subject(project, "Character", "Cid")
    patch subject_path(cid), params: { subject: { ref: " speaker/12 " } }
    expect(cid.reload.ref).to eq("speaker/12")
    other = make_subject(project, "Creature", "Gull")
    patch subject_path(other), params: { subject: { ref: "speaker/12" } }
    expect(page.text).to include("Ref has already been taken")

    get project_skeleton_path(project)
    expect(response.headers["Content-Disposition"]).to include("the-drowned-coast-skeleton.json")
    expect(response.parsed_body).to include("baible_skeleton" => 1, "source" => "baible")
    expect(response.parsed_body["assets"]).to include(include("ref" => "speaker/12", "kind" => "Character", "name" => "Cid"))
  end
end
