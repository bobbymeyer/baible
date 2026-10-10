# frozen_string_literal: true

# A run's LoRA file, as fetched back from the ComfyUI that trained it: to
# put in a ComfyUI's LoRAs by hand, or keep.
class Trainings::LorasController < ApplicationController
  include TrainingScoped

  def show
    raise Refusal, "#{@training.title} has no LoRA file in baible" unless @training.lora_file.attached?

    send_data @training.lora_file.download, filename: @training.lora_file.filename.to_s,
                                            type: "application/octet-stream", disposition: "attachment"
  end
end
