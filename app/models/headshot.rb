# frozen_string_literal: true

# The head of a full-body sprite, cut square for a portrait to be drawn
# from (docs/HANDOFF.md "Chains": a sprite, then a portrait, then
# expressions). The figure is found by its transparency (or by trimming
# the plain background), the top of it taken as a square about a third of
# its height, centred on it, and the background flattened to plain grey
# so the image model has a picture to start from, not a hole.
module Headshot
  GROUND = [ 232, 232, 232 ].freeze
  SHARE = 0.34 # of the figure's height: head and shoulders

  def self.of(bytes, share: SHARE)
    require "vips" # libvips, loaded only when cutting
    image = Vips::Image.new_from_buffer(bytes, "")
    left, top, width, height = bounds(image)
    side = [ (height * share).round, 32 ].max.clamp(1, [ image.width, image.height ].min)
    x = (left + (width / 2) - (side / 2)).clamp(0, image.width - side)
    y = [ top - (side * 0.08).round, 0 ].max.clamp(0, image.height - side)
    crop = image.crop(x, y, side, side)
    crop = crop.flatten(background: GROUND) if crop.has_alpha?
    crop.write_to_buffer(".png")
  end

  # [left, top, width, height] of the figure, or the whole image when nothing stands out
  # (or it is too small to look).
  def self.bounds(image)
    whole = [ 0, 0, image.width, image.height ]
    return whole if image.width < 8 || image.height < 8

    left, top, width, height = if image.has_alpha?
      image.extract_band(image.bands - 1).find_trim(threshold: 10, background: [ 0 ])
    else
      image.find_trim(threshold: 20, background: image.getpoint(0, 0).first(3))
    end
    width.zero? || height.zero? ? whole : [ left, top, width, height ]
  rescue Vips::Error
    whole
  end
end
