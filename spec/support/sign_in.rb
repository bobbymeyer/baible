# frozen_string_literal: true

# Accounts in request specs. Every request spec signs in unless it is
# tagged `signed_out: true`.
module SignIn
  PASSWORD = "correct horse battery"

  def make_user(email = "someone-#{SecureRandom.hex(3)}@example.com")
    User.create!(email_address: email, password: PASSWORD)
  end

  def sign_in_as(user)
    post session_path, params: { email_address: user.email_address, password: PASSWORD }
    user
  end
end

RSpec.configure do |config|
  config.include SignIn, type: :request
  config.before(type: :request) do |example|
    @user = sign_in_as(make_user) unless example.metadata[:signed_out]
  end
end
