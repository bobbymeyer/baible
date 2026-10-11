# frozen_string_literal: true

# A project as a design skeleton (Skeleton.export): its kinds, entries and
# subjects as placeholders, with their refs. The format another project's
# export writes, and a start for a new project like this one.
class Projects::SkeletonsController < ApplicationController
  include ProjectScoped

  def show
    send_data JSON.pretty_generate(Skeleton.export(@project)), type: :json, disposition: params[:inline] ? "inline" : "attachment",
                                                               filename: "#{@project.name.parameterize}-skeleton.json"
  end
end
