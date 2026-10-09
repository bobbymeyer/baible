class CreateTrainings < ActiveRecord::Migration[8.1]
  def change
    # One LoRA training run for an entry (docs/HANDOFF.md "The LoRA loop"),
    # frozen at start like a recipe: which picks, their captions, the base
    # model and the settings. "set" is a set kept without training it.
    create_table :trainings do |t|
      t.references :entry, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.integer :version, null: false
      t.string :status, null: false, default: "set"
      t.text :error
      t.string :trigger, null: false
      t.string :model, null: false
      t.string :family, null: false
      t.json :settings, null: false, default: {}
      t.json :items, null: false, default: []
      t.string :lora
      t.string :workflow
      t.string :comfy_prompt_id
      t.datetime :submitted_at
      t.float :run_seconds
      t.timestamps
    end
    add_index :trainings, %i[entry_id version], unique: true

    # The word its LoRA answers to, and the run whose LoRA it uses.
    add_column :entries, :trigger, :string
    add_reference :entries, :training, foreign_key: true
  end
end
