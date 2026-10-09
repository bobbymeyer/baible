# frozen_string_literal: true

namespace :night do
  desc "One tick of the night shift, now (production runs it every minute under Solid Queue)"
  task tick: :environment do
    outcome = NightShift.tick!
    puts outcome.is_a?(ApplicationRecord) ? "Let #{outcome.class.name} #{outcome.id} go" : outcome.to_s.tr("_", " ")
  end
end
