# frozen_string_literal: true

# Generating (docs/HANDOFF.md "Batches, candidates, picks"): starting a
# batch first saves the subject's own layer as written in the studio (its
# notes, model and LoRAs; lyrics and length for audio), then queues the
# candidates with ComfyUI for the subject, one variant, or every variant at
# once. The studio's strips fill in as they land. Or queue it for the night
# window instead (tonight: one target, or "every" variant; NightShift).
class Subjects::BatchesController < ApplicationController
  include SubjectScoped

  def create
    @subject.update!(subject_params) if params.key?(:subject)
    tonight = params[:tonight].present?
    options = { count: params[:count].presence || Comfy.config[:candidates], write: params[:write] != "0",
                transparent: { "1" => true, "0" => false }[params[:transparent]], draft: params[:draft] == "1", tonight: tonight }
    if (source = chain_source)
      options.merge!(source: source, denoise: denoise_for(source), draft: false)
    end

    if params[:every] == "1" || params[:tonight] == "every"
      raise Refusal, "#{@subject.name} has no variants yet" if @subject.variants.empty?

      @subject.variants.each { |variant| Batch.start!(@subject, variant: variant, **options) }
    else
      Batch.start!(@subject, variant: target_variant, **options)
    end
    if tonight
      redirect_to subject_path(@subject, anchor: "batches"), status: :see_other,
                  notice: "Queued for tonight (#{NightShift.window.label}). It'll be on the Overnight page in the morning."
    else
      redirect_to subject_path(@subject, anchor: "batches"), status: :see_other
    end
  end

  # Throw the candidates away, or take a batch off tonight's queue.
  def destroy
    @subject.batches.find(params[:id]).destroy!
    redirect_to subject_path(@subject, anchor: "batches"), status: :see_other
  end

  private

  def subject_params
    allowed = @subject.audio? ? [ :notes, :model, :lyrics, :seconds ] : [ :notes, :model, { loras: {} } ]
    params.expect(subject: allowed)
  end

  def target_variant
    @subject.variants.find(params[:variant_id]) if params[:variant_id].present?
  end

  # A pick of this project's to redraw from (images only), with its head
  # cut out of it when asked (Headshot).
  def chain_source
    return if params[:from_pick_id].blank? || @subject.audio?

    pick = @project.picks.find(params[:from_pick_id])
    raise Refusal, "#{pick.title} has no image to draw from" unless pick.image?

    { "pick_id" => pick.id, "crop" => (params[:crop] == "head" ? "head" : nil) }
  end

  # As asked, or config/comfy.yml's `chain` for cutting a head or not.
  def denoise_for(source)
    return params[:denoise].to_f if params[:denoise].present?

    chain = Comfy.config.fetch(:chain, {})
    source["crop"] == "head" ? chain.fetch(:head_denoise, 0.55) : chain.fetch(:denoise, 0.45)
  end
end
