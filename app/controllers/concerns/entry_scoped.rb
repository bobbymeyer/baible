# frozen_string_literal: true

# Loads the entry in the URL (entry_id), and its project, for a controller
# nested under it.
module EntryScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_entry
  end

  private

  def set_entry
    @entry = Entry.find(params[:entry_id])
    @project = @entry.project
  end
end
