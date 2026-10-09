# frozen_string_literal: true

# An entry's page in the bible (show): its lore, its look and every subject
# made of it, kind by kind; and editing it. Deleting it keeps its subjects.
class EntriesController < ApplicationController
  before_action :set_entry

  def show
  end

  def edit
  end

  def update
    if @entry.update(params.expect(entry: [ :name, :look, :trigger, :lore, { loras: {} } ]))
      redirect_to entry_path(@entry), notice: "Saved.", status: :see_other
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @entry.destroy!
    redirect_to project_entries_path(@project), notice: "#{@entry.name} is gone; its subjects stay.", status: :see_other
  end

  private

  def set_entry
    @entry = Entry.find(params[:id])
    @project = @entry.project
  end
end
