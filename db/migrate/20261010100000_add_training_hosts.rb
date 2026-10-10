class AddTrainingHosts < ActiveRecord::Migration[8.1]
  def change
    # Where a run trains: "local" (the ComfyUI baible generates on) or
    # "remote" (the training host, TRAINING_COMFY_URL: a rented GPU, say).
    # host_started_at: when baible started a rented pod for it; host_note:
    # what went wrong with the host (a pod it couldn't stop costs money).
    add_column :trainings, :host, :string, null: false, default: "local"
    add_column :trainings, :host_started_at, :datetime
    add_column :trainings, :host_note, :text
  end
end
