# frozen_string_literal: true

# A note on an entry (docs/HANDOFF.md "Entries and model sheets"): an open
# question, a decision, a note to whoever draws it next, with who wrote it
# and when. Notes are for people and never go in a prompt. Only the author
# can take one back; one whose author's account is gone stays, unsigned.
class Note < ApplicationRecord
  belongs_to :entry
  belongs_to :user, optional: true

  normalizes :body, with: ->(value) { value.to_s.strip.presence }

  validates :body, presence: true

  def author = user&.email_address || "someone no longer here"
end
