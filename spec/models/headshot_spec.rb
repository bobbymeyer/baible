# frozen_string_literal: true

require "rails_helper"

RSpec.describe Headshot do
  # A cut-out figure: transparent canvas, an opaque body in the lower middle with a head on top.
  def figure(width: 200, height: 400)
    canvas = Vips::Image.black(width, height, bands: 4)
    body = Vips::Image.black(60, 200, bands: 4).new_from_image([ 200, 40, 40, 255 ])
    head = Vips::Image.black(40, 40, bands: 4).new_from_image([ 240, 200, 180, 255 ])
    canvas.insert(body, 70, 180).insert(head, 80, 140).write_to_buffer(".png")
  end

  it "cuts the head and shoulders square from the top of the figure, on plain ground" do
    bytes = described_class.of(figure)
    crop = Vips::Image.new_from_buffer(bytes, "")
    expect(crop.width).to eq(crop.height)
    expect(crop.width).to eq((240 * 0.34).round) # a third of the figure's 240 px height
    expect(crop.has_alpha?).to be(false)
    expect(crop.getpoint(0, 0).first(3)).to eq(Headshot::GROUND) # the corner is ground, not a hole
    centre = crop.getpoint(crop.width / 2, crop.height / 2).first(3)
    expect(centre).to eq([ 240, 200, 180 ]) # the head is in the middle
  end

  it "takes the whole picture when nothing stands out, and never asks for more than there is" do
    tiny = described_class.of(FakeComfy.png)
    expect(Vips::Image.new_from_buffer(tiny, "").width).to eq(1)
    blank = Vips::Image.black(64, 64, bands: 3).write_to_buffer(".png")
    expect(Vips::Image.new_from_buffer(described_class.of(blank), "").width).to eq(32)
  end
end
