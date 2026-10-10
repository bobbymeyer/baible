# frozen_string_literal: true

# Deriving subjects from one (docs/HANDOFF.md "Derived kinds and sheets"):
# Cid's portrait, turnaround or design sheet, in one click, named as he is
# (kind_id), or one in every kind that derives from his and has none of him
# yet, nor anything else of his name ("every"). Another name is the New
# subject form's (parent_id).
class Subjects::DerivationsController < ApplicationController
  include SubjectScoped

  def create
    kinds = @subject.derivable_kinds
    if params[:kind_id] == "every"
      wanted = kinds.reject { |kind| @subject.derived_subjects.exists?(kind: kind) || kind.subjects.exists?(name: @subject.name) }
      made = wanted.map { |kind| derive!(kind) }
      raise Refusal, "#{@subject.name} has one of every kind derived from #{@subject.kind.name} already" if made.empty?

      redirect_to subject_path(@subject, anchor: "derived"), notice: "Made #{made.map { |s| s.kind.name }.to_sentence} of #{@subject.name}.", status: :see_other
    else
      kind = kinds.find { |k| k.id.to_s == params[:kind_id].to_s } or raise Refusal, "That kind doesn't derive from #{@subject.kind.name}"
      redirect_to subject_path(derive!(kind)), notice: "#{kind.name} of #{@subject.name} added.", status: :see_other
    end
  end

  private

  def derive!(kind)
    if kind.subjects.exists?(name: @subject.name)
      raise Refusal, "#{kind.name} already has a #{@subject.name}: add this one from New subject, with another name"
    end

    @project.subjects.create!(kind: kind, parent: @subject, name: @subject.name)
  end
end
