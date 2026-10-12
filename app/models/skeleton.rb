# frozen_string_literal: true

# A design skeleton (docs/HANDOFF.md "Import: skeletons"): the list of
# assets another project needs, as JSON, imported as placeholders, subjects
# with nothing picked yet, for baible to make. Each asset can carry the
# other project's own name for it (`ref`), which every pick of it gives back
# in its sidecar and the manifest, so the files find their way home.
#
#   { "baible_skeleton": 1, "source": "polychrome",
#     "project": { "name", "description", "style", "negative", "sound" },
#     "kinds":   [{ "name", "medium", "prompt", "from", "derive", "variants": { name => words }, … }],
#     "entries": [{ "name", "look", "lore" }],
#     "assets":  [{ "ref", "kind", "name", "entry", "from", "notes", "lyrics", "seconds",
#                   "variants": [{ "name", "prompt", "ref" }] }] }
#
# Importing again is safe: what baible has is matched (an asset by its ref,
# else its kind and name; the rest by name), only what's new is made, and
# blanks are filled; nothing edited in baible is overwritten. Anything wrong
# stops the whole import, with every problem listed (Invalid).
module Skeleton
  VERSION = 1
  MAX_BYTES = 5.megabytes

  class Invalid < StandardError
    attr_reader :problems

    def initialize(problems)
      @problems = Array(problems)
      super(@problems.first(3).join("; "))
    end
  end

  # What an import did, for the page.
  Report = Struct.new(:project, :new_project, :kinds, :entries, :subjects, :matched, :variants, :elsewhere, keyword_init: true) do
    def summary
      parts = [ new_project ? "Made #{project.name}" : "Imported into #{project.name}" ]
      parts << "#{kinds.size} new #{'kind'.pluralize(kinds.size)} (#{kinds.to_sentence})" if kinds.any?
      parts << ActionController::Base.helpers.pluralize(entries, "new entry", plural: "new entries") if entries.positive?
      parts << ActionController::Base.helpers.pluralize(subjects, "new placeholder")
      parts << "#{matched} already here" if matched.positive?
      parts << ActionController::Base.helpers.pluralize(variants, "new variant") if variants.positive?
      parts << "#{elsewhere} with a ref not in this skeleton, left as they are" if elsewhere.positive?
      parts.join("; ") + "."
    end
  end

  module_function

  # Import a skeleton (JSON text, or parsed), into the project it names or
  # the one given. Returns a Report; raises Invalid.
  def import!(input, project: nil)
    data = parse(input)
    Importer.new(data, project).run
  end

  def parse(input)
    raise Invalid, "The skeleton is over #{MAX_BYTES / 1.megabyte} MB" if input.is_a?(String) && input.bytesize > MAX_BYTES

    data = input.is_a?(String) ? JSON.parse(input) : input
    raise Invalid, "A skeleton is a JSON object" unless data.is_a?(Hash)
    unless data["baible_skeleton"] == VERSION
      raise Invalid, "Not a skeleton baible reads: \"baible_skeleton\" must be #{VERSION} (it is #{data['baible_skeleton'].inspect})"
    end

    data
  rescue JSON::ParserError => e
    raise Invalid, "That isn't JSON: #{e.message.truncate(120)}"
  end

  # A project as a skeleton: its kinds, entries and every subject, with
  # their refs. Importing it elsewhere makes the same placeholders.
  def export(project)
    {
      "baible_skeleton" => VERSION,
      "source" => "baible",
      "project" => project.slice("name", "description", "style", "negative", "sound").compact,
      "kinds" => project.kinds.map { |kind| kind_row(kind) },
      "entries" => project.entries.map { |entry| entry.slice("name", "look", "lore").compact },
      "assets" => project.subjects.includes(:kind, :entry, :variants, parent: :kind)
                         .sort_by { |subject| [ subject.kind.position, subject.kind.id, subject.name.downcase ] }
                         .map { |subject| asset_row(subject) }
    }
  end

  def kind_row(kind)
    row = kind.slice("name", "medium", "prompt", "negative", "width", "height", "transparent", "seconds").compact
    if kind.parent
      row["from"] = kind.parent.name
      row.merge!(kind.slice("derive", "derive_denoise", "derive_weight").compact) unless kind.sheet?
    end
    row["sheet_of"] = kind.sheet_kinds.map(&:name) if kind.sheet? && kind.sheet_kind_ids.any?
    row["variants"] = kind.variant_presets.to_h { |preset| [ preset["name"], preset["prompt"].to_s ] } if kind.variant_presets.any?
    row
  end

  def asset_row(subject)
    {
      "ref" => subject.ref, "kind" => subject.kind.name, "name" => subject.name, "entry" => subject.entry&.name,
      "from" => (subject.parent.ref || { "kind" => subject.parent.kind.name, "name" => subject.parent.name } if subject.parent),
      "notes" => subject.notes, "lyrics" => subject.lyrics, "seconds" => subject.seconds,
      "variants" => (subject.variants.map { |variant| variant.slice("name", "prompt", "ref").compact } if subject.variants.any?)
    }.compact
  end

  # One import, in one transaction: kinds, entries, then assets, then which
  # asset derives from which (so the order in the file doesn't matter).
  class Importer
    def initialize(data, project)
      @data = data
      @project = project
      @problems = []
      @report = Report.new(kinds: [], entries: 0, subjects: 0, matched: 0, variants: 0, elsewhere: 0)
    end

    def run
      ActiveRecord::Base.transaction do
        project!
        kinds!
        entries!
        placed = Array(@data["assets"]).each_with_index.filter_map { |asset, i| asset!(asset, "assets[#{i}]") }
        placed.each { |subject, from, path| parent!(subject, from, path) }
        refs = placed.map(&:first).filter_map(&:ref)
        @report.elsewhere = @project.subjects.where.not(ref: nil).where.not(ref: refs).count
        raise Invalid, @problems if @problems.any?
      end
      @report.project = @project
      @report
    end

    private

    def project!
      fields = hash(@data["project"], "project").slice("name", "description", "style", "negative", "sound").transform_values(&:to_s)
      @project ||= Project.find_by(name: fields["name"].to_s.strip)
      @report.new_project = @project.nil?
      if @project
        fields.except("name").each { |key, value| @project[key] = value if @project[key].blank? && value.present? }
        @project.save!
      else
        raise Invalid, "project: a name is needed for a new project" if fields["name"].blank?

        @project = Project.create!(fields)
        @project.add_starter_kinds! unless @data["starter_kinds"] == false
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Invalid, "project: #{e.record.errors.full_messages.to_sentence}"
    end

    # A kind derives from one the project has or one before it in the file.
    def kinds!
      known = @project.kinds.pluck(:name)
      rows = Array(@data["kinds"]).each_with_index.filter_map do |row, i|
        next problem("kinds[#{i}]: a kind is an object with a name") unless row.is_a?(Hash) && row["name"].present?
        next problem("kinds[#{i}] (#{row['name']}): \"from\" #{row['from'].inspect} is no kind before it") if row["from"].present? && known.exclude?(row["from"])

        known << row["name"].to_s.strip
        Kind.row_attributes(row)
      end
      @report.kinds = @project.add_kinds!(rows).map(&:name)
    rescue ActiveRecord::RecordInvalid => e
      problem("kinds (#{e.record.name}): #{e.record.errors.full_messages.to_sentence}")
    end

    def entries!
      Array(@data["entries"]).each_with_index do |row, i|
        next problem("entries[#{i}]: an entry is an object with a name") unless row.is_a?(Hash) && row["name"].present?

        entry_named(row["name"], look: row["look"], lore: row["lore"])
      end
    end

    # The entry of that name, made if it's new; its blanks filled.
    def entry_named(name, look: nil, lore: nil)
      entry = @project.entries.find_or_initialize_by(name: name.to_s.strip)
      @report.entries += 1 if entry.new_record?
      entry.look = look.to_s if entry.look.blank? && look.present?
      entry.lore = lore.to_s if entry.lore.blank? && lore.present?
      entry.save!
      entry
    end

    # [subject, its "from", path], or nil after a problem.
    def asset!(asset, path)
      return problem("#{path}: an asset is an object") unless asset.is_a?(Hash)

      path = "#{path} (#{asset['name'] || asset['ref']})"
      kind = @project.kinds.find_by(name: asset["kind"].to_s.strip)
      return problem("#{path}: no kind called #{asset['kind'].inspect} in #{@project.name}, nor in the skeleton's kinds") unless kind
      return problem("#{path}: a name is needed") if asset["name"].blank?

      ref = asset["ref"].presence&.to_s
      return problem("#{path}: the ref #{ref} is used twice") if ref && (@refs ||= Set.new).add?(ref).nil?

      subject = (ref && @project.subjects.find_by(ref: ref)) || @project.subjects.find_by(kind: kind, name: asset["name"].to_s.strip)
      if subject
        @report.matched += 1
      else
        subject = @project.subjects.new(kind: kind, name: asset["name"].to_s)
        @report.subjects += 1
      end
      fill(subject, asset, ref)
      subject.save!
      variants!(subject, asset["variants"], path)
      [ subject, asset["from"], path ]
    rescue ActiveRecord::RecordInvalid => e
      problem("#{path}: #{e.record.errors.full_messages.to_sentence}")
    end

    def fill(subject, asset, ref)
      subject.ref ||= ref if ref && !@project.subjects.where.not(id: subject.id).exists?(ref: ref)
      subject.notes = asset["notes"].to_s if subject.notes.blank? && asset["notes"].present?
      subject.lyrics = asset["lyrics"].to_s if subject.lyrics.blank? && asset["lyrics"].present?
      subject.seconds ||= asset["seconds"].to_i if asset["seconds"].present?
      subject.entry ||= entry_named(asset["entry"]) if asset["entry"].present?
    end

    # [{ "name", "prompt", "ref" }], or { name => words }.
    def variants!(subject, rows, path)
      rows = rows.map { |name, words| { "name" => name, "prompt" => words } } if rows.is_a?(Hash)
      Array(rows).each do |row|
        next problem("#{path}: a variant is an object with a name") unless row.is_a?(Hash) && row["name"].present?

        variant = subject.variants.find_or_initialize_by(name: row["name"].to_s.strip)
        @report.variants += 1 if variant.new_record?
        variant.position = subject.variants.maximum(:position).to_i + 1 if variant.new_record?
        variant.prompt = row["prompt"].to_s if variant.prompt.blank? && row["prompt"].present?
        variant.ref ||= row["ref"].to_s if row["ref"].present?
        variant.save!
      end
    end

    # "from": another asset's ref, or { "kind", "name" }. A subject that
    # already derives from something keeps it.
    def parent!(subject, from, path)
      return if from.blank? || subject.parent

      parent = if from.is_a?(Hash)
        @project.subjects.joins(:kind).find_by(name: from["name"].to_s.strip, kinds: { name: from["kind"].to_s.strip })
      else
        @project.subjects.find_by(ref: from.to_s)
      end
      return problem("#{path}: \"from\" #{from.to_json} is no asset here") unless parent

      subject.update!(parent: parent)
    rescue ActiveRecord::RecordInvalid => e
      problem("#{path}: #{e.record.errors.full_messages.to_sentence}")
    end

    def hash(value, path)
      return value if value.is_a?(Hash)

      @project ? {} : raise(Invalid, "#{path}: an object with at least a name")
    end

    def problem(message)
      @problems << message
      nil
    end
  end
end
