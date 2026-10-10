# frozen_string_literal: true

# A project's kinds (its "art direction"): the framing, size, model and
# LoRAs for each kind of asset, the middle layer of every recipe.
class Projects::KindsController < ApplicationController
  include ProjectScoped

  before_action :set_kind, only: %i[edit update destroy]

  def index
    @kinds = @project.kinds.includes(:subjects)
  end

  def new
    @kind = @project.kinds.new(medium: params[:medium].presence_in(Kind::MEDIA) || "image")
  end

  def create
    @kind = @project.kinds.new(kind_params.merge(position: @project.kinds.maximum(:position).to_i + 1))
    if @kind.save
      redirect_to project_kinds_path(@project, anchor: helpers.dom_id(@kind)), notice: "#{@kind.name} added.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @kind.update(kind_params)
      redirect_to project_kinds_path(@project, anchor: helpers.dom_id(@kind)), notice: "#{@kind.name} saved.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @kind.destroy
      redirect_to project_kinds_path(@project), notice: "#{@kind.name} is gone.", status: :see_other
    else
      redirect_to project_kinds_path(@project), alert: "#{@kind.name} still has subjects: move or delete them first.", status: :see_other
    end
  end

  private

  def set_kind
    @kind = @project.kinds.find(params[:id])
  end

  def kind_params
    params.expect(kind: [ :name, :medium, :prompt, :negative, :model, :width, :height, :transparent, :seconds, :variant_presets,
                          :learned_workflow_id, { loras: {} } ])
  end
end
