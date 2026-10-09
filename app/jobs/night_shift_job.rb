# frozen_string_literal: true

# A tick of the night shift (NightShift), every minute (config/recurring.yml):
# lets the next thing queued for tonight into ComfyUI when it may.
class NightShiftJob < ApplicationJob
  def perform
    outcome = NightShift.tick!
    Rails.logger.info("[night shift] let #{outcome.class.name} #{outcome.id} go") if outcome.is_a?(ApplicationRecord)
  end
end
