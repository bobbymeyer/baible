class CreateSubjectsAndVariants < ActiveRecord::Migration[8.1]
  def change
    # The thing being made: a goblin, Cid, the harbour town, its theme.
    create_table :subjects do |t|
      t.references :project, null: false, foreign_key: true
      t.references :kind, null: false, foreign_key: true
      t.string :name, null: false
      t.text :notes
      t.string :model
      t.json :loras, null: false, default: []
      t.text :lyrics
      t.integer :seconds
      t.timestamps
    end
    add_index :subjects, %i[kind_id name], unique: true

    # A detail layer after the subject ("happy", "winter", "battle version").
    create_table :variants do |t|
      t.references :subject, null: false, foreign_key: true
      t.string :name, null: false
      t.text :prompt
      t.integer :position, null: false, default: 0
      t.timestamps
    end
    add_index :variants, %i[subject_id name], unique: true
  end
end
