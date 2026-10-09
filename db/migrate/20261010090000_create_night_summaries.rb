class CreateNightSummaries < ActiveRecord::Migration[8.1]
  def change
    # One summary a night, written when the window closes (NightSummary):
    # kept for the Overnight page, and sent to MORNING_WEBHOOK_URL if set.
    create_table :night_summaries do |t|
      t.datetime :opened_at, null: false
      t.datetime :closed_at, null: false
      t.text :text, null: false
      t.json :payload, null: false, default: {}
      t.datetime :sent_at
      t.text :error
      t.timestamps
    end
    add_index :night_summaries, :closed_at, unique: true
  end
end
