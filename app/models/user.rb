# Someone who can sign in. Everyone signed in shares every project: baible
# is a workshop for one person or a small team, not a multi-tenant service.
# The first account is made from the console or `bin/rails users:create`
# (README "Setup"); there is no sign-up page.
class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :notes, dependent: :nullify
  has_many :standing_orders, dependent: :nullify
  has_many :picks, dependent: :nullify
  has_many :canon_picks, class_name: "Pick", foreign_key: :canon_by_id, inverse_of: :canon_by, dependent: :nullify

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 10 }, allow_nil: true
end
