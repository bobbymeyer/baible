# frozen_string_literal: true

module ArtHelper
  MISSING = "Not on ComfyUI"

  # A LoRA stack, in order, switched-off ones struck through.
  def lora_stack(loras)
    return "none" if loras.empty?

    safe_join(loras.map do |lora|
      text = "#{lora['name']} #{lora['strength']}"
      lora.fetch("on", true) && !lora["strength"].to_f.zero? ? text : tag.s(text, title: "switched off")
    end, " · ")
  end

  # The installed models, grouped by the family each would run as, in the
  # order config/comfy.yml lists the families: [[label, [file, ...]], ...].
  def model_groups(caps)
    order = Comfy::Family.configured.keys
    caps.models.map { |file| [ Comfy::Family.for(file, capabilities: caps), file ] }
        .group_by { |family, _| [ order.index(family.slug) || order.size, family.label ] }
        .sort_by { |(rank, label), _| [ rank, label ] }
        .map { |(_, label), rows| [ label, rows.map(&:last).sort_by(&:downcase) ] }
  end

  # The installed LoRAs, grouped by the subfolder they sit in (the usual way
  # of keeping them apart by family), loose ones first.
  def lora_groups(caps)
    caps.loras.group_by { |file| File.dirname(file) }
        .sort_by { |dir, _| dir == "." ? "" : dir.downcase }
        .map { |dir, files| [ dir == "." ? "LoRAs" : dir, files.sort_by(&:downcase) ] }
  end

  # A strict picker from grouped choices. A value that isn't installed any
  # more stays selectable, in its own group, so saving doesn't lose it.
  def grouped_picker(name, value, groups, blank:, **options)
    value = value.to_s
    groups += [ [ MISSING, [ value ] ] ] if value.present? && groups.none? { |_, files| files.include?(value) }
    choices = groups.map { |label, files| [ label, files.map { |file| [ file, file ] } ] }
    select_tag name, grouped_options_for_select(choices, value), include_blank: blank, **options
  end

  # Existing rows plus blank ones to fill in (no JS needed to add rows).
  def rows_with_blanks(rows, blanks: 1)
    Array(rows) + Array.new(blanks) { {} }
  end

  # How long ComfyUI spent on something: "43s", "2m 5s".
  def run_time(seconds)
    return unless seconds

    seconds < 60 ? "#{seconds.round}s" : "#{(seconds / 60).floor}m #{(seconds % 60).round}s"
  end

  # Whether ComfyUI answers, for the generate buttons.
  def comfy_reachable? = Comfy.capabilities.reachable?

  # The project's standing image picks to start a batch from, grouped by subject,
  # for a select: [[subject, [[label, id], ...]], ...].
  def chain_choices(project)
    picks = Pick.standing(project.picks.images.includes(:variant, subject: :kind)).reject { |pick| pick.subject.sheet? }.sort_by { |pick| [ pick.subject.name.downcase, pick.variant&.position.to_i, pick.variant_id.to_i ] }
    picks.group_by(&:subject).map do |subject, rows|
      [ "#{subject.name} (#{subject.kind.name})", rows.map { |pick| [ "#{pick.variant ? pick.variant.name : 'itself'} · seed #{pick.seed}", pick.id ] } ]
    end
  end

  # The subjects another can derive from, grouped by kind, for a select: every
  # image subject but the one itself (Subject#parent_fits says which fit).
  def parent_choices(project, except: nil)
    project.kinds.select(&:image?).filter_map do |kind|
      subjects = kind.subjects.reject { |subject| subject == except }.sort_by { |subject| subject.name.downcase }
      [ kind.name, subjects.map { |subject| [ subject.name, subject.id ] } ] if subjects.any?
    end
  end
end
