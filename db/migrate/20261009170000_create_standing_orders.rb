class CreateStandingOrders < ActiveRecord::Migration[8.1]
  def change
    # Work the night shift plans for itself every night (docs/HANDOFF.md
    # "Standing orders"): fill a project's gaps, keep going until canon, or
    # train an entry's LoRA once it has enough canon pictures.
    create_table :standing_orders do |t|
      t.references :project, null: false, foreign_key: true
      t.references :kind, foreign_key: true
      t.references :entry, foreign_key: true
      t.references :user, foreign_key: true
      t.string :action, null: false
      t.integer :count, null: false, default: 4
      t.integer :nightly_limit, null: false, default: 20
      t.integer :min_pictures, null: false, default: 12
      t.string :model
      t.boolean :enabled, null: false, default: true
      t.datetime :planned_at
      t.text :report
      t.timestamps
    end
  end
end
