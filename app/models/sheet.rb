# frozen_string_literal: true

# A sheet: the picks of a subject and everything derived from it, laid out
# as one picture (docs/HANDOFF.md "Derived kinds and sheets"). Cid's design
# sheet is Cid, his portrait and its expressions, his turnaround, his
# battle sprite, his costumes: a row for each, each picture labelled.
#
# What stands for each target (canon, else current) is chosen when the
# sheet's batch starts (#plan, frozen in its recipe like any recipe), then
# laid out by libvips (#compose), in baible, not ComfyUI: nothing is drawn,
# only arranged. Audio, and other sheets, are left out.
module Sheet
  CELL = 512 # each picture's height
  GAP = 24
  PER_ROW = 6 # pictures, before a row wraps
  INK = 32 # labels: dark grey on white
  PAPER = [ 255, 255, 255 ].freeze

  # A picture on the sheet has gone since it was planned.
  class Missing < StandardError; end

  module_function

  # { "title", "rows" => [{ "label", "subject_id", "cells" => [{ "pick_id", "label" }] }] }
  # for a sheet's subject: its parent, then what derives from it, of the
  # sheet's kinds, each with its variants; targets with no image pick are left out.
  def plan(sheet)
    root = sheet.parent or return { "title" => sheet.name, "rows" => [] }
    kinds = sheet.kind.sheet_kinds
    subjects = [ root, *root.descendants ].select { |subject| kinds.include?(subject.kind) }
    rows = subjects.filter_map do |subject|
      cells = [ nil, *subject.variants ].filter_map do |variant|
        pick = subject.pick_for(variant)
        { "pick_id" => pick.id, "label" => variant ? variant.name : subject.kind.name } if pick&.image?
      end
      label = subject == root || subject.name == root.name ? subject.kind.name : "#{subject.kind.name}: #{subject.name}"
      { "label" => label, "subject_id" => subject.id, "cells" => cells } if cells.any?
    end
    { "title" => "#{root.name}: #{sheet.kind.name}", "rows" => rows }
  end

  # The sheet as PNG bytes. Raises Missing when a picture on it has gone
  # since it was planned.
  def compose(plan)
    require "vips" # libvips, loaded only when composing
    blocks = [ text(plan["title"], size: 56) ]
    plan["rows"].each do |row|
      blocks << text(row["label"], size: 32)
      row["cells"].each_slice(PER_ROW) { |cells| blocks << strip(cells) }
    end
    blocks.compact!
    width = blocks.map(&:width).max + (2 * GAP)
    height = blocks.sum(&:height) + (GAP * (blocks.size + 1))
    canvas = Vips::Image.black(width, height, bands: 3).new_from_image(PAPER).cast(:uchar)
    y = GAP
    blocks.each do |block|
      canvas = canvas.insert(block, GAP, y)
      y += block.height + GAP
    end
    canvas.write_to_buffer(".png")
  end

  # One line of pictures, each with its label under it.
  def strip(cells)
    tiles = cells.map do |cell|
      pick = Pick.find_by(id: cell["pick_id"])
      raise Missing, "A picture on the sheet (#{cell['label']}) is gone; lay it out again" unless pick&.file&.attached?

      picture = flat(Vips::Image.new_from_buffer(pick.file.download, ""))
      picture = picture.resize(CELL.to_f / picture.height)
      label = text(cell["label"], size: 24)
      label ? column([ picture, label ]) : picture
    end
    row(tiles)
  end

  # On white, three bands of 8 bits.
  def flat(image)
    image = image.colourspace(:srgb) if image.interpretation != :srgb
    image = image.flatten(background: PAPER) if image.has_alpha?
    image = image.extract_band(0, n: 3) if image.bands > 3
    image = image.bandjoin([ image, image ]) if image.bands == 1
    image.cast(:uchar)
  end

  # Dark text on white, or nil where libvips has no fonts to draw it with
  # (the sheet is laid out without labels; the recipe still names each one).
  def text(words, size:)
    mask = Vips::Image.text(words.to_s, dpi: 72, font: "sans #{size}")
    ink = (mask * ((INK - 255) / 255.0) + 255).cast(:uchar)
    ink.bandjoin([ ink, ink ])
  rescue Vips::Error
    nil
  end

  def row(images) = arrange(images, across: true)
  def column(images) = arrange(images, across: false)

  def arrange(images, across:)
    width = across ? images.sum(&:width) + (GAP * (images.size - 1)) : images.map(&:width).max
    height = across ? images.map(&:height).max : images.sum(&:height) + (8 * (images.size - 1))
    canvas = Vips::Image.black(width, height, bands: 3).new_from_image(PAPER).cast(:uchar)
    offset = 0
    images.each do |image|
      canvas = across ? canvas.insert(image, offset, 0) : canvas.insert(image, 0, offset)
      offset += (across ? image.width + GAP : image.height + 8)
    end
    canvas
  end
end
