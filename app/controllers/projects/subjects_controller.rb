# frozen_string_literal: true

# Adding a subject to a project, in one of its kinds, and of one of its
# entries if it depicts one (Cid's portrait), maybe derived from another
# subject (Cid's portrait from Cid, the character; it then depicts his
# entry). It starts with the kind's variant presets (a portrait's
# expressions).
class Projects::SubjectsController < ApplicationController
  include ProjectScoped

  def new
    kind = @project.kinds.find_by(id: params[:kind_id]) || @project.kinds.first
    parent = @project.subjects.find_by(id: params[:parent_id])
    kind = parent.derivable_kinds.first || kind if parent && kind && kind.parent_kinds.exclude?(parent.kind)
    entry = @project.entries.find_by(id: params[:entry_id]) || parent&.entry
    @subject = @project.subjects.new(kind: kind, entry: entry, parent: parent, name: entry&.name || parent&.name)
  end

  def create
    @subject = @project.subjects.new(params.expect(subject: [ :name, :kind_id, :entry_id, :parent_id, :notes, :lyrics, :seconds ]))
    @subject.kind = @project.kinds.find_by(id: @subject.kind_id)
    @subject.entry = @project.entries.find_by(id: @subject.entry_id)
    @subject.parent = @project.subjects.find_by(id: @subject.parent_id)
    if @subject.save
      redirect_to subject_path(@subject), notice: "#{@subject.name} added.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end
end
