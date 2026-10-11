# frozen_string_literal: true

# Importing a design skeleton (docs/HANDOFF.md "Import: skeletons"): a JSON
# file of the assets another project needs, uploaded or pasted, made into
# placeholders in the project it names (a new one if need be), or in the
# one it's imported from (project_id).
class SkeletonsController < ApplicationController
  def new
    @project = Project.find_by(id: params[:project_id])
  end

  def create
    @project = Project.find_by(id: params[:project_id])
    report = Skeleton.import!(input, project: @project)
    redirect_to project_path(report.project), notice: report.summary, status: :see_other
  rescue Skeleton::Invalid => e
    @problems = e.problems
    render :new, status: :unprocessable_content
  end

  private

  def input
    file = params[:file]
    text = file.respond_to?(:read) ? file.read(Skeleton::MAX_BYTES + 1) : params[:json].to_s
    raise Skeleton::Invalid, "Choose a file, or paste the JSON" if text.blank?

    text
  end
end
