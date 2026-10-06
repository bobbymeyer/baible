# frozen_string_literal: true

# A detail layer after a subject (docs/HANDOFF.md "Variants and chains"):
# "happy" adds "smiling happily" to Cid's portrait. Each variant has its own
# batches and its own pick; by default its first candidate tries the
# subject's own pick's seed, and it can be redrawn from that pick.
class Variant < ApplicationRecord
  belongs_to :subject
  has_many :batches, dependent: :destroy
  has_many :picks, dependent: :destroy

  normalizes :name, :prompt, with: ->(value) { value.to_s.strip.presence }

  validates :name, presence: true, uniqueness: { scope: :subject_id }
end
