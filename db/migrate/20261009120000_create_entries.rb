class CreateEntries < ActiveRecord::Migration[8.1]
  def change
    # One thing in the world, across every kind it's made in: Cid, the
    # harbour town. Its look is a layer of every image of it; its lore never
    # goes in a prompt.
    create_table :entries do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name, null: false
      t.text :look
      t.json :loras, null: false, default: []
      t.text :lore
      t.timestamps
    end
    add_index :entries, %i[project_id name], unique: true

    add_reference :subjects, :entry, foreign_key: true
  end
end
