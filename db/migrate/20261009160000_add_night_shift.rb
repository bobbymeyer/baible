class AddNightShift < ActiveRecord::Migration[8.1]
  def change
    # A batch queued for the night window (NightShift): it waits as
    # "scheduled", and it never replaces another batch, so a morning's
    # Generate can't throw away the night's work before it's reviewed.
    add_column :batches, :night, :boolean, null: false, default: false
    # When the night shift let it go: its time with ComfyUI counts from then,
    # not from when it was queued that afternoon.
    add_column :batches, :released_at, :datetime

    # The window, on the Settings page: "23:00" to "07:00" in a time zone.
    add_column :site_settings, :night_start, :string
    add_column :site_settings, :night_end, :string
    add_column :site_settings, :night_zone, :string
  end
end
