class CreateBatchesCandidatesAndPicks < ActiveRecord::Migration[8.1]
  def change
    # One round of generation for a subject (or one of its variants): the
    # recipe, frozen when it starts, and its candidates.
    create_table :batches do |t|
      t.references :subject, null: false, foreign_key: true
      t.references :variant, foreign_key: true
      t.json :recipe, null: false, default: {}
      t.string :status, null: false, default: "queued"
      t.text :error
      t.datetime :submitted_at
      t.timestamps
    end

    # One ComfyUI prompt in a batch, with its own seed, and what it made.
    create_table :candidates do |t|
      t.references :batch, null: false, foreign_key: true
      t.integer :position, null: false
      t.integer :seed, null: false
      t.string :comfy_prompt_id
      t.string :status, null: false, default: "queued"
      t.text :error
      t.boolean :transparent
      t.float :run_seconds
      t.timestamps
    end

    # The chosen file for a subject (or a variant), with how it was made.
    create_table :picks do |t|
      t.references :subject, null: false, foreign_key: true
      t.references :variant, foreign_key: true
      t.integer :seed
      t.text :prompt
      t.json :recipe, null: false, default: {}
      t.float :run_seconds
      t.timestamps
    end
    add_index :picks, %i[subject_id variant_id], unique: true
  end
end
