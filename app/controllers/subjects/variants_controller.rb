# frozen_string_literal: true

# A subject's variants: detail layers after it ("happy": "smiling happily").
class Subjects::VariantsController < ApplicationController
  include SubjectScoped

  def create
    variant = @subject.variants.new(variant_params.merge(position: @subject.variants.maximum(:position).to_i + 1))
    if variant.save
      redirect_to subject_path(@subject, anchor: "variants"), notice: "#{variant.name} added.", status: :see_other
    else
      redirect_to subject_path(@subject, anchor: "variants"), alert: variant.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def update
    variant = @subject.variants.find(params[:id])
    if variant.update(variant_params)
      redirect_to subject_path(@subject, anchor: "variants"), notice: "#{variant.name} saved.", status: :see_other
    else
      redirect_to subject_path(@subject, anchor: "variants"), alert: variant.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    variant = @subject.variants.find(params[:id])
    variant.destroy!
    redirect_to subject_path(@subject, anchor: "variants"), notice: "#{variant.name} is gone, with its pick.", status: :see_other
  end

  private

  def variant_params
    params.expect(variant: [ :name, :prompt ])
  end
end
