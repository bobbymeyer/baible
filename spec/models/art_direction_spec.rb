# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Composing a recipe in layers" do
  describe ArtDirection do
    it "cleans LoRA rows from a form: blanks dropped, strength a float, 1.0 by default, on unless switched off" do
      rows = { "0" => { "name" => " house.safetensors ", "strength" => "0.75", "on" => "1" }, "1" => { "name" => "hero", "strength" => "", "on" => "0" },
               "2" => { "name" => "" } }
      expect(described_class.loras(rows)).to eq([ { "name" => "house.safetensors", "strength" => 0.75, "on" => true },
                                                  { "name" => "hero", "strength" => 1.0, "on" => false } ])
      expect(described_class.loras([ { name: "x", strength: 99 } ])).to eq([ { "name" => "x", "strength" => 5.0, "on" => true } ])
    end

    it "stacks LoRAs in layer order: a later layer naming one again changes it in place, or switches it off" do
      project = [ { "name" => "house", "strength" => 0.8 }, { "name" => "grain", "strength" => 0.3 } ]
      kind = [ { "name" => "profile", "strength" => 1 } ]
      subject = [ { "name" => "house", "strength" => 0.4 }, { "name" => "grain", "strength" => 0.3, "on" => false } ]
      stack = described_class.stack_loras(project, kind, subject)
      expect(stack.map { |l| [ l["name"], l["strength"], l["on"] ] }).to eq([ [ "house", 0.4, true ], [ "grain", 0.3, false ], [ "profile", 1.0, true ] ])
      expect(described_class.active_loras(stack).map { |l| l["name"] }).to eq(%w[house profile])
    end

    it "takes the model from the lowest layer that names one" do
      expect(described_class.pick_model("", "kind.safetensors", "project.safetensors", "default.safetensors")).to eq("kind.safetensors")
      expect(described_class.pick_model(nil, " ", nil, "default.safetensors")).to eq("default.safetensors")
    end

    it "joins prompt parts, skipping blanks and doubled commas" do
      expect(described_class.join_prompt("pixel art,", nil, " ", "full body", "Goblin")).to eq("pixel art, full body, Goblin")
    end
  end

  describe "a subject's recipe" do
    let(:project) { make_project }
    let(:goblin) { make_subject(project, "Creature", "Goblin") }

    it "starts a project with the kinds in config/comfy.yml, each new subject with its kind's variants" do
      expect(project.kinds.map(&:name)).to include("Creature", "Portrait", "Music")
      expect(project.kinds.find_by!(name: "Creature").prompt).to include("profile view")
      project.add_starter_kinds! # again: nothing doubled
      expect(project.kinds.where(name: "Creature").count).to eq(1)
      cid = make_subject(project, "Portrait", "Cid")
      expect(cid.variants.map(&:name)).to eq(%w[happy sad angry surprised worried determined])
      expect(cid.variants.first.prompt).to eq("smiling happily")
    end

    it "composes project style, then kind framing, then the subject, with the family's words first and every layer's LoRAs" do
      project.update!(style: "16-bit pixel art", negative: "photo", model: "pixelXL.safetensors",
                      loras: [ { "name" => "house", "strength" => 0.8 } ])
      goblin.kind.update!(prompt: "profile view, full body", negative: "cropped", width: 768, height: 768,
                          model: "ponyDiffusionV6XL.safetensors", loras: [ { "name" => "sprites", "strength" => 1 } ])
      goblin.update!(notes: "green skin, a rusty knife", loras: [ { "name" => "house", "strength" => 0.5 } ])

      expect(goblin.recipe).to eq(
        "medium" => "image",
        "model" => "ponyDiffusionV6XL.safetensors",
        "family" => "sdxl",
        "loras" => [ { "name" => "house", "strength" => 0.5, "on" => true }, { "name" => "sprites", "strength" => 1.0, "on" => true } ],
        "positive" => "score_9, score_8_up, score_7_up, 16-bit pixel art, profile view, full body, Goblin, green skin, a rusty knife",
        "negative" => "score_4, score_5, score_6, photo, cropped",
        "width" => 896, "height" => 896, "transparent" => true,
        "parts" => { "prefix" => "score_9, score_8_up, score_7_up", "style" => "16-bit pixel art", "framing" => "profile view, full body",
                     "entry" => "", "subject" => "Goblin, green skin, a rusty knife", "detail" => "" }
      )

      goblin.update!(model: "anima-preview.safetensors")
      expect(goblin.recipe).to include("model" => "anima-preview.safetensors", "family" => "anima")
      expect(goblin.recipe["positive"]).to start_with("masterpiece, best quality, 16-bit pixel art")
    end

    it "puts a variant's words last, and uses the configured model by default" do
      happy = goblin.variants.create!(name: "happy", prompt: "grinning")
      recipe = goblin.recipe(happy)
      expect(recipe["positive"]).to end_with("Goblin, grinning")
      expect(recipe["parts"]["detail"]).to eq("grinning")
      expect(recipe["model"]).to eq(Comfy.config[:model])
      expect(goblin.layers(happy).map { |layer| layer["role"] }).to eq(%w[Project Kind Subject Variant])
    end

    it "puts an entry's look after the kind's framing, word for word, and its LoRAs between the kind's and the subject's" do
      project.update!(loras: [ { "name" => "house", "strength" => 0.8 } ])
      grax = project.entries.create!(name: "Grax", look: "one tusk, a scarred left cheek",
                                     loras: [ { "name" => "grax", "strength" => 0.9 }, { "name" => "house", "strength" => 0.4 } ])
      goblin.update!(entry: grax, notes: "crouching", loras: [ { "name" => "grax", "strength" => 0.7 } ])

      recipe = goblin.recipe
      expect(recipe["positive"]).to end_with("#{goblin.kind.prompt}, one tusk, a scarred left cheek, Goblin, crouching")
      expect(recipe["parts"]).to include("entry" => "one tusk, a scarred left cheek", "subject" => "Goblin, crouching")
      expect(recipe["loras"]).to eq([ { "name" => "house", "strength" => 0.4, "on" => true }, { "name" => "grax", "strength" => 0.7, "on" => true } ])
      expect(goblin.layers.map { |layer| layer["role"] }).to eq(%w[Project Kind Entry Subject])

      theme = make_subject(project, "Music", "Grax's theme", entry: grax, notes: "war drums")
      expect(theme.recipe["positive"]).not_to include("tusk") # a look isn't a sound
      expect(theme.layers.map { |layer| layer["role"] }).to eq(%w[Project Kind Subject])
    end

    it "keeps an entry to its own project" do
      elsewhere = Project.create!(name: "Elsewhere").entries.create!(name: "Grax")
      expect(goblin.update(entry: elsewhere)).to be(false)
      expect(goblin.errors[:entry]).to be_present
    end

    it "composes audio from the project's sound, the kind's tags and the subject's, with its lyrics and length" do
      project.update!(sound: "medieval folk", model: "pixelXL.safetensors")
      theme = make_subject(project, "Music", "Harbour theme", notes: "sea shanty, accordion", lyrics: "[verse]\nThe tide", seconds: 30)
      expect(theme.recipe).to eq(
        "medium" => "audio", "model" => "ace_step_v1_3.5b.safetensors",
        "positive" => "medieval folk, game soundtrack, loopable, instrumental, sea shanty, accordion",
        "lyrics" => "[verse]\nThe tide", "seconds" => 30,
        "parts" => { "style" => "medieval folk", "framing" => "game soundtrack, loopable, instrumental", "subject" => "sea shanty, accordion", "detail" => "" }
      )
      theme.update!(seconds: nil)
      expect(theme.recipe["seconds"]).to eq(60) # the kind's
    end
  end
end
