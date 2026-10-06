class CreateProjectsAndKinds < ActiveRecord::Migration[8.1]
  def change
    # A world or setting: the top layer of every recipe (docs/HANDOFF.md).
    create_table :projects do |t|
      t.string :name, null: false
      t.text :description
      t.text :style
      t.text :negative
      t.string :model
      t.json :loras, null: false, default: []
      t.text :sound
      t.timestamps
    end
    add_index :projects, :name, unique: true

    # A kind of asset in a project: its framing, size, medium and so on.
    create_table :kinds do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.string :medium, null: false, default: "image"
      t.text :prompt
      t.text :negative
      t.string :model
      t.json :loras, null: false, default: []
      t.integer :width, null: false, default: 1024
      t.integer :height, null: false, default: 1024
      t.boolean :transparent, null: false, default: false
      t.integer :seconds, null: false, default: 60
      t.json :variant_presets, null: false, default: []
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :kinds, %i[project_id name], unique: true
  end
end
