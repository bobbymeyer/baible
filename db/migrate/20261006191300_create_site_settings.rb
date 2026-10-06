class CreateSiteSettings < ActiveRecord::Migration[8.1]
  def change
    # One row: where ComfyUI and the language model are, and default models.
    # Tokens, headers and passwords stay in the environment.
    create_table :site_settings do |t|
      t.string :comfy_url
      t.string :comfy_model
      t.string :music_model
      t.string :rmbg_model
      t.string :llm_url
      t.string :llm_model
      t.integer :draft_size
      t.integer :draft_steps
      t.float :draft_denoise
      t.integer :candidates
      t.timestamps
    end
  end
end
