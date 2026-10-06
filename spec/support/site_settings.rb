# frozen_string_literal: true

# SiteSetting remembers its row in memory; each example starts from none.
RSpec.configure do |config|
  config.before { SiteSetting.forget! if defined?(SiteSetting) }
end
