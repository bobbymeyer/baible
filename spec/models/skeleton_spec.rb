# frozen_string_literal: true

require "rails_helper"

# Design skeletons (docs/HANDOFF.md "Import: skeletons"): another project's
# list of needed assets, imported as placeholders, and a project exported as one.
RSpec.describe Skeleton do
  let(:skeleton) do
    {
      "baible_skeleton" => 1, "source" => "polychrome",
      "project" => { "name" => "The Drowned Coast", "style" => "ink wash" },
      "kinds" => [ { "name" => "Battle sprite", "from" => "Character", "derive" => "picture", "width" => 832, "height" => 1216,
                     "variants" => { "attack" => "lunging forward" } } ],
      "entries" => [ { "name" => "Cid", "look" => "eyepatch over the left eye", "lore" => "The harbourmaster." } ],
      "assets" => [
        # Derived before what it derives from: the order in the file doesn't matter.
        { "ref" => "speaker/12/portrait", "kind" => "Portrait", "name" => "Cid", "from" => "speaker/12",
          "variants" => [ { "name" => "happy", "ref" => "speaker/12/portrait/happy" }, { "name" => "smug", "prompt" => "a smug grin" } ] },
        { "ref" => "speaker/12", "kind" => "Character", "name" => "Cid", "entry" => "Cid", "notes" => "red coat" },
        { "ref" => "speaker/12/battle", "kind" => "Battle sprite", "name" => "Cid", "from" => { "kind" => "Character", "name" => "Cid" } },
        { "ref" => "bestiary/3", "kind" => "Creature", "name" => "Drowned sailor", "notes" => "barnacled" }
      ]
    }
  end

  it "makes a project of placeholders, with the kinds, entries and variants it names, and each ref" do
    report = described_class.import!(JSON.generate(skeleton))
    project = report.project
    expect(project).to have_attributes(name: "The Drowned Coast", style: "ink wash")
    expect(project.kinds.find_by!(name: "Portrait")).to be_present # the starter kinds, then the skeleton's
    expect(project.kinds.find_by!(name: "Battle sprite")).to have_attributes(parent: project.kinds.find_by!(name: "Character"), derive: "picture",
                                                                              variant_presets: [ { "name" => "attack", "prompt" => "lunging forward" } ])
    expect(report.summary).to eq("Made The Drowned Coast; 1 new kind (Battle sprite); 1 new entry; 4 new placeholders; 1 new variant.")

    cid = project.subjects.find_by!(ref: "speaker/12")
    expect(cid).to have_attributes(name: "Cid", notes: "red coat", entry: project.entries.find_by!(name: "Cid", look: "eyepatch over the left eye"))
    portrait = project.subjects.find_by!(ref: "speaker/12/portrait")
    expect(portrait).to have_attributes(parent: cid, entry: cid.entry)
    expect(portrait.variants.find_by!(name: "happy").ref).to eq("speaker/12/portrait/happy") # a preset, given its ref
    expect(portrait.variants.find_by!(name: "smug").prompt).to eq("a smug grin")
    expect(project.subjects.find_by!(ref: "speaker/12/battle")).to have_attributes(parent: cid)
    expect(project.subjects.find_by!(ref: "bestiary/3").picks).to be_empty
  end

  it "imports again without making twice or overwriting what was changed here" do
    project = described_class.import!(skeleton).project
    cid = project.subjects.find_by!(ref: "speaker/12")
    cid.update!(notes: "red coat, brass buttons", name: "Cid the Elder")
    project.subjects.find_by!(ref: "bestiary/3").update!(notes: nil)
    project.subjects.create!(kind: project.kinds.find_by!(name: "Item"), name: "Lantern", ref: "armory/9")

    again = skeleton.deep_dup
    again["assets"][1]["notes"] = "a blue coat"
    again["assets"][3]["notes"] = "barnacled, a broken lantern"
    report = described_class.import!(again)
    expect(report.summary).to eq("Imported into The Drowned Coast; 0 new placeholders; 4 already here; 1 with a ref not in this skeleton, left as they are.")
    expect(cid.reload).to have_attributes(name: "Cid the Elder", notes: "red coat, brass buttons") # matched by ref; not overwritten
    expect(project.subjects.find_by!(ref: "bestiary/3").notes).to eq("barnacled, a broken lantern") # a blank, filled
    expect(project.subjects.count).to eq(5)
  end

  it "imports into the project it's given, whatever the file names" do
    project = make_project("Elsewhere")
    report = described_class.import!(skeleton.merge("project" => { "name" => "Ignored" }), project: project)
    expect(report.project).to eq(project)
    expect(Project.exists?(name: "Ignored")).to be(false)
    expect(project.subjects.count).to eq(4)
  end

  it "lists every problem and imports nothing" do
    bad = skeleton.deep_dup
    bad["kinds"] << { "name" => "Echo", "from" => "Nothing like it" }
    bad["assets"] << { "ref" => "bestiary/3", "kind" => "Creature", "name" => "Twin" }
    bad["assets"] << { "kind" => "Spaceship", "name" => "Gull" }
    bad["assets"] << { "kind" => "Portrait", "name" => "Nobody", "from" => "speaker/99" }
    bad["assets"] << { "kind" => "Portrait", "name" => "Goblin", "from" => "bestiary/3" }

    expect { described_class.import!(bad) }.to raise_error(Skeleton::Invalid) { |error|
      expect(error.problems).to contain_exactly(
        "kinds[1] (Echo): \"from\" \"Nothing like it\" is no kind before it",
        "assets[4] (Twin): the ref bestiary/3 is used twice",
        "assets[5] (Gull): no kind called \"Spaceship\" in The Drowned Coast, nor in the skeleton's kinds",
        "assets[6] (Nobody): \"from\" \"speaker/99\" is no asset here",
        "assets[7] (Goblin): Parent must be a Character (or derived from one)"
      )
    }
    expect(Project.count).to eq(0)

    expect { described_class.import!("{ nope") }.to raise_error(Skeleton::Invalid, /isn't JSON/)
    expect { described_class.import!(JSON.generate("assets" => [])) }.to raise_error(Skeleton::Invalid, /"baible_skeleton" must be 1/)
    expect { described_class.import!(JSON.generate("baible_skeleton" => 1)) }.to raise_error(Skeleton::Invalid, /project/)
  end

  it "imports the example in docs/SKELETON.md as it says" do
    report = described_class.import!(Rails.root.join("docs/skeleton.example.json").read)
    project = report.project
    expect(report.summary).to eq("Made The Drowned Coast; 1 new kind (Battle sprite); 1 new entry; 7 new placeholders; 1 new variant.")
    cid = project.subjects.find_by!(ref: "speaker/12")
    expect(project.subjects.where(parent: cid).pluck(:ref)).to contain_exactly("speaker/12/portrait", "speaker/12/battle", "speaker/12/winter")
    expect(project.subjects.find_by!(ref: "speaker/12/battle").variants.find_by!(name: "attack")).to have_attributes(ref: "speaker/12/battle/attack", prompt: "lunging forward, weapon raised")
    expect(project.subjects.find_by!(ref: "music/harbour")).to have_attributes(seconds: 90, medium: "audio")
  end

  it "exports a project as a skeleton that makes the same placeholders elsewhere" do
    project = described_class.import!(skeleton).project
    exported = described_class.export(project)
    expect(exported["assets"].find { |asset| asset["ref"] == "speaker/12/portrait" }).to include("from" => "speaker/12", "entry" => "Cid")
    expect(exported["kinds"].find { |kind| kind["name"] == "Portrait" }).to include("from" => "Character", "derive" => "head")
    expect(exported["kinds"].find { |kind| kind["name"] == "Character design sheet" }).to include("medium" => "sheet", "from" => "Character")

    copy = described_class.import!(JSON.generate(exported.merge("project" => exported["project"].merge("name" => "The Copy")))).project
    describe_subject = ->(subject) { [ subject.ref, subject.kind.name, subject.name, subject.parent&.ref, subject.entry&.name, subject.variants.map(&:name).sort ] }
    expect(copy.subjects.map(&describe_subject).sort_by(&:first)).to eq(project.subjects.map(&describe_subject).sort_by(&:first))
    expect(copy.kinds.map(&:name)).to eq(project.kinds.map(&:name))
  end
end
