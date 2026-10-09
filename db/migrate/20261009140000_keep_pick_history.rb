class KeepPickHistory < ActiveRecord::Migration[8.1]
  # Picks are kept (docs/HANDOFF.md "Picks: history and canon"): a target has
  # a history, one current pick and at most one canon pick. Every pick made
  # before this was its target's only one, so it is current.
  def up
    remove_index :picks, %i[subject_id variant_id]
    add_column :picks, :current, :boolean, null: false, default: false
    add_reference :picks, :user, foreign_key: true
    add_column :picks, :canon_at, :datetime
    add_reference :picks, :canon_by, foreign_key: { to_table: :users }
    execute "UPDATE picks SET current = 1"

    # One current and one canon per target; a subject's own target has no
    # variant, and SQLite counts NULLs as distinct, hence IFNULL.
    add_index :picks, "subject_id, IFNULL(variant_id, 0)", unique: true, where: "current", name: "index_picks_one_current_per_target"
    add_index :picks, "subject_id, IFNULL(variant_id, 0)", unique: true, where: "canon_at IS NOT NULL", name: "index_picks_one_canon_per_target"
  end

  def down
    remove_index :picks, name: "index_picks_one_canon_per_target"
    remove_index :picks, name: "index_picks_one_current_per_target"
    execute "DELETE FROM picks WHERE NOT current"
    remove_reference :picks, :canon_by, foreign_key: { to_table: :users }
    remove_column :picks, :canon_at
    remove_reference :picks, :user, foreign_key: true
    remove_column :picks, :current
    add_index :picks, %i[subject_id variant_id], unique: true
  end
end
