# frozen_string_literal: true

# The name of a Turbo stream, for have_broadcasted_to: stream(campaign, :table).
module Streams
  def stream(*streamables)
    Turbo::StreamsChannel.send(:stream_name_from, streamables)
  end
end

RSpec.configure { |config| config.include Streams }
