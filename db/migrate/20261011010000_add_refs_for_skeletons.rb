# frozen_string_literal: true

# What another project calls a subject or variant, kept from the skeleton it
# came in (docs/HANDOFF.md "Import: skeletons") and given back in its
# sidecar and the manifest, so that project knows which file is which.
class AddRefsForSkeletons < ActiveRecord::Migration[8.1]
  def change
    add_column :subjects, :ref, :string
    add_index :subjects, %i[project_id ref], unique: true, where: "ref IS NOT NULL"
    add_column :variants, :ref, :string
  end
end
