# frozen_string_literal: true

# Kinds derived from kinds (a Portrait from a Character), subjects derived
# from subjects (Cid's portrait from Cid), and sheets: a kind whose subjects
# are composed from the picks of what derives from their parent
# (docs/HANDOFF.md "Derived kinds and sheets").
class AddDerivationToKindsAndSubjects < ActiveRecord::Migration[8.1]
  def change
    add_reference :kinds, :parent, foreign_key: false, index: true
    add_column :kinds, :derive, :string, null: false, default: "words"
    add_column :kinds, :derive_denoise, :float
    add_column :kinds, :sheet_kind_ids, :json, null: false, default: []
    add_reference :subjects, :parent, foreign_key: false, index: true
  end
end
