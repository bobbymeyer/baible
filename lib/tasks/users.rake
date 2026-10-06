# frozen_string_literal: true

namespace :users do
  desc "Make an account, or set an existing one's password: EMAIL=... PASSWORD=... bin/rails users:create"
  task create: :environment do
    email = ENV["EMAIL"].presence || (print("Email: ") || $stdin.gets.to_s.strip)
    password = ENV["PASSWORD"].presence || begin
      require "io/console"
      print "Password (10 characters or more): "
      $stdin.noecho(&:gets).to_s.strip.tap { puts }
    end
    user = User.find_or_initialize_by(email_address: email.strip.downcase)
    created = user.new_record?
    user.password = password
    if user.save
      puts "#{created ? 'Made' : 'Updated'} #{user.email_address}. Sign in at /session/new."
    else
      abort user.errors.full_messages.to_sentence
    end
  end
end
