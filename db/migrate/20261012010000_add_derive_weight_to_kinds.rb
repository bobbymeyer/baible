# frozen_string_literal: true

# How strongly a kind that draws from its parent's picture as a reference
# (derive "reference", IP-Adapter) holds to it (docs/HANDOFF.md "Derived
# kinds and sheets").
class AddDeriveWeightToKinds < ActiveRecord::Migration[8.1]
  def change
    add_column :kinds, :derive_weight, :float
  end
end
