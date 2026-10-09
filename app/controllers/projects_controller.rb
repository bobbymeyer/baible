# frozen_string_literal: true

# Projects: worlds or settings, each with its own house style (the top
# layer of every recipe), kinds and subjects.
class ProjectsController < ApplicationController
  before_action :set_project, only: %i[show edit update destroy]

  def index
    @projects = Project.order(:name).includes(:kinds)
  end

  def show
    @kinds = @project.kinds.includes(subjects: [ :entry, :variants, { picks: { file_attachment: :blob } } ])
  end

  def new
    @project = Project.new
  end

  def create
    @project = Project.new(project_params)
    if @project.save
      @project.add_starter_kinds! if params[:starter_kinds] != "0"
      redirect_to @project, notice: "#{@project.name} is ready.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @project.update(project_params)
      redirect_to @project, notice: "Saved.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @project.destroy!
    redirect_to projects_path, notice: "#{@project.name} is gone, with everything made in it.", status: :see_other
  end

  private

  def set_project
    @project = Project.find(params[:id])
  end

  def project_params
    params.expect(project: [ :name, :description, :style, :negative, :model, :sound, { loras: {} } ])
  end
end
