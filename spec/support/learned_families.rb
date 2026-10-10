# frozen_string_literal: true

# LearnedFamily remembers its families in memory for a few seconds; each
# example starts from none, as its rows were rolled back.
RSpec.configure do |config|
  config.before { LearnedFamily.forget! if defined?(LearnedFamily) }
end
