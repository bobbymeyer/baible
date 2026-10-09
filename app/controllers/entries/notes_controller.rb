# frozen_string_literal: true

# Notes on an entry: anyone signed in adds one, signed with their account;
# only its author takes it back.
class Entries::NotesController < ApplicationController
  include EntryScoped

  def create
    note = @entry.notes.new(params.expect(note: [ :body ]).merge(user: Current.user))
    if note.save
      redirect_to entry_path(@entry, anchor: "notes"), notice: "Noted.", status: :see_other
    else
      redirect_to entry_path(@entry, anchor: "notes"), alert: note.errors.full_messages.to_sentence, status: :see_other
    end
  end

  def destroy
    Current.user.notes.where(entry: @entry).find(params[:id]).destroy!
    redirect_to entry_path(@entry, anchor: "notes"), notice: "Note taken back.", status: :see_other
  end
end
