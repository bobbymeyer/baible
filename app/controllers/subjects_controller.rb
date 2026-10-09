# frozen_string_literal: true

# A subject's studio (show): its layers, picks, the generate form and the
# candidate strips; and its own layer (edit), its name, kind and entry.
class SubjectsController < ApplicationController
  before_action :set_subject

  def show
  end

  def edit
  end

  def update
    attrs = subject_params
    attrs[:kind] = @project.kinds.find(attrs.delete(:kind_id)) if attrs.key?(:kind_id)
    attrs[:entry] = @project.entries.find_by(id: attrs.delete(:entry_id)) if attrs.key?(:entry_id)
    if @subject.update(attrs)
      redirect_to subject_path(@subject), notice: "Saved.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @subject.destroy!
    redirect_to project_path(@project), notice: "#{@subject.name} is gone.", status: :see_other
  end

  private

  def set_subject
    @subject = Subject.find(params[:id])
    @project = @subject.project
  end

  def subject_params
    params.expect(subject: [ :name, :kind_id, :entry_id, :notes, :model, :lyrics, :seconds, { loras: {} } ])
  end
end
