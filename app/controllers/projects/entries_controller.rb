# frozen_string_literal: true

# A project's entries, the bible: one thing in the world (Cid, the harbour
# town) across every kind it's made in. The index is the bible's contents.
class Projects::EntriesController < ApplicationController
  include ProjectScoped

  def index
    @entries = @project.entries.includes(:notes, subjects: [ :kind, { picks: { file_attachment: :blob } } ])
  end

  def new
    @entry = @project.entries.new
  end

  def create
    @entry = @project.entries.new(params.expect(entry: [ :name, :look, :lore, { loras: {} } ]))
    if @entry.save
      redirect_to entry_path(@entry), notice: "#{@entry.name} added.", status: :see_other
    else
      render :new, status: :unprocessable_content
    end
  end
end
