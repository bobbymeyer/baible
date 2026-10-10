class CreateLearnedFamiliesAndWorkflows < ActiveRecord::Migration[8.1]
  def change
    # How to run a model config/comfy.yml doesn't know (docs/HANDOFF.md
    # "Unknown models and new workflows"): proposed by the language model,
    # checked against the server, tried, accepted by a person, then used
    # like a configured family.
    create_table :learned_families do |t|
      t.string :slug, null: false
      t.string :label, null: false
      t.string :model, null: false
      t.json :match, null: false, default: []
      t.json :settings, null: false, default: {}
      t.string :status, null: false, default: "asking"
      t.text :error
      t.text :log
      t.references :user, foreign_key: true
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :learned_families, :slug, unique: true

    # A ComfyUI graph the builder can't make, written by the language model
    # from a person's description, with placeholders baible fills per
    # candidate ({{prompt}}, {{seed}}, {{prefix}} ...).
    create_table :learned_workflows do |t|
      t.string :name, null: false
      t.text :purpose, null: false
      t.json :graph, null: false, default: {}
      t.string :outline
      t.string :status, null: false, default: "asking"
      t.text :error
      t.text :log
      t.references :user, foreign_key: true
      t.references :accepted_by, foreign_key: { to_table: :users }
      t.datetime :accepted_at
      t.timestamps
    end
    add_index :learned_workflows, :name, unique: true

    # A test render of either, through ComfyUI.
    create_table :trials do |t|
      t.references :learnable, polymorphic: true, null: false
      t.string :status, null: false, default: "queued"
      t.text :error
      t.string :prompt, null: false
      t.integer :seed, null: false
      t.string :comfy_prompt_id
      t.datetime :submitted_at
      t.float :run_seconds
      t.timestamps
    end

    # A kind can make its pictures with an accepted learned workflow.
    add_reference :kinds, :learned_workflow, foreign_key: true
  end
end
