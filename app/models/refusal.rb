# frozen_string_literal: true

# When the app says no ("only a draft can be made properly"): a model
# raises Refusal, and whoever asked sees it as an alert. ArgumentError means
# a bug, and crashes.
class Refusal < StandardError; end
