class CreateNotes < ActiveRecord::Migration[8.1]
  def change
    # A running log on an entry: who said what, when. Never in a prompt.
    create_table :notes do |t|
      t.references :entry, null: false, foreign_key: true
      t.references :user, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end
  end
end
