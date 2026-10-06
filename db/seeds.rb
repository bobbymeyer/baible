# The first account, when EMAIL and PASSWORD are set (bin/rails db:seed);
# otherwise `bin/rails users:create` asks for them. See the README.
if ENV["EMAIL"].present? && ENV["PASSWORD"].present?
  user = User.find_or_initialize_by(email_address: ENV["EMAIL"].strip.downcase)
  user.update!(password: ENV["PASSWORD"])
  puts "Account: #{user.email_address}"
end
