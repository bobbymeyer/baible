# frozen_string_literal: true

namespace :services do
  desc "Check the app can reach ComfyUI (and the language model, if set), step by step"
  task check: :environment do
    puts "In a container: #{ConnectionCheck.in_container? ? 'yes' : 'no'}"
    [ ConnectionCheck.comfy, ConnectionCheck.llm ].compact.each do |doctor|
      doctor.steps.each { |step| puts "#{step.ok ? '  ok ' : 'FAIL '} #{step.label}: #{step.detail}" }
      puts
    end
  end
end
