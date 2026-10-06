# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Audio with ACE-Step", type: :request do
  include ActiveJob::TestHelper

  let(:project) { make_project(sound: "medieval folk") }
  let(:theme) { make_subject(project, "Music", "The long road", notes: "lute, slow, melancholic") }
  let(:comfy) { FakeComfy.new(capabilities: FakeComfy.capabilities(checkpoints: [ "ace_step_v1_3.5b.safetensors" ])) }

  def node(graph, type) = graph.values.find { |n| n["class_type"] == type }

  it "makes candidates in ComfyUI from the layers, lyrics and length, and picks one" do
    get subject_path(theme)
    expect(response.body).to include("Lyrics (blank for instrumental)", "ACE-Step")
    expect(page.at("#batch_draft")).to be_nil # no drafts or backgrounds for audio

    post subject_batches_path(theme), params: { count: 2, subject: { notes: "lute, slow", lyrics: "", seconds: "30", model: "" } }
    batch = theme.batch_for(nil)
    expect(batch.recipe).to include("medium" => "audio", "positive" => "medieval folk, game soundtrack, loopable, instrumental, lute, slow", "seconds" => 30)

    BatchJob.new.perform(batch.reload, client: comfy)
    graph = comfy.submitted.first
    expect(graph.values.map { |n| n["class_type"] }).to include("CheckpointLoaderSimple", "EmptyAceStepLatentAudio", "TextEncodeAceStepAudio", "KSampler", "VAEDecodeAudio", "SaveAudioMP3")
    expect(node(graph, "TextEncodeAceStepAudio")["inputs"]).to include("tags" => batch.recipe["positive"], "lyrics" => "[instrumental]")
    expect(node(graph, "EmptyAceStepLatentAudio")["inputs"]["seconds"]).to eq(30.0)
    expect(node(graph, "SaveAudioMP3")["inputs"]["filename_prefix"]).to eq("baible/the-long-road-#{batch.candidates.first.seed}")
    expect(batch.reload.recipe["workflow"]).to start_with("CheckpointLoaderSimple")

    comfy.finish!("prompt-1", "prompt-2")
    BatchJob.new.perform(batch.reload, client: comfy)
    candidate = batch.candidates.first
    expect(candidate).to have_attributes(status: "done", transparent: nil)
    expect(candidate.file.filename.to_s).to eq("the-long-road-#{candidate.seed}.mp3")
    expect(candidate.file.content_type).to eq("audio/mpeg")

    get subject_path(theme)
    expect(page.css(".candidate audio").size).to eq(2)

    post candidate_pick_path(candidate)
    pick = theme.pick_for(nil)
    expect(pick).to be_audio
    expect(pick.sidecar).to include("medium" => "audio", "seconds" => 30, "lyrics" => nil, "model" => "ace_step_v1_3.5b.safetensors", "width" => nil)
  end

  it "says why when ComfyUI hasn't the checkpoint" do
    post subject_batches_path(theme), params: { count: 1 }
    batch = theme.batch_for(nil)
    BatchJob.new.perform(batch.reload, client: FakeComfy.new)
    expect(batch.reload).to have_attributes(status: "failed", error: a_string_including("ace_step_v1_3.5b.safetensors isn't on ComfyUI"))
  end

  it "uses the lyrics, and the kind's or subject's own checkpoint" do
    theme.kind.update!(model: "ace_step_v1_5.safetensors")
    theme.update!(lyrics: "[verse]\nThe road runs on")
    caps = FakeComfy.capabilities(checkpoints: [ "ace_step_v1_5.safetensors" ])
    graph = Comfy::Music.build(theme.recipe, seed: 7, prefix: "x", capabilities: caps)
    expect(node(graph, "CheckpointLoaderSimple")["inputs"]["ckpt_name"]).to eq("ace_step_v1_5.safetensors")
    expect(node(graph, "TextEncodeAceStepAudio")["inputs"]["lyrics"]).to eq("[verse]\nThe road runs on")
  end
end
