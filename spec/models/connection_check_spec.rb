# frozen_string_literal: true

require "rails_helper"

RSpec.describe ConnectionCheck do
  def doctor(url) = described_class.new(url: url, name: "ComfyUI", probe: -> { "answers." })

  it "says a loopback address inside a container is the container itself" do
    allow(described_class).to receive(:in_container?).and_return(true)
    step = doctor("http://127.0.0.1:8188").steps.last
    expect(step).to have_attributes(ok: false, label: "Where")
    expect(step.detail).to include("host.docker.internal", "tailnet")
  end

  it "stops at a name that doesn't resolve, with what to do" do
    allow(Resolv).to receive(:getaddresses).and_return([])
    allow(Addrinfo).to receive(:getaddrinfo).and_raise(SocketError)
    expect(doctor("http://host.docker.internal:8188").steps.last.detail).to include("extra_hosts")
    expect(doctor("https://comfy.tail1234.ts.net").steps.last.detail).to include("MagicDNS")
  end

  it "tells a refused connection from a missing route, and never shows a password" do
    allow(described_class).to receive(:in_container?).and_return(false)
    allow(Resolv).to receive(:getaddresses).and_return([ "10.0.0.9" ])
    allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
    steps = doctor("http://me:s3cret@comfy.lan:8188").steps
    expect(steps.first.detail).to eq("http://comfy.lan:8188 (basic auth in the URL)")
    expect(steps.last.detail).to include("--listen")
    expect(steps.map(&:detail).join).not_to include("s3cret")

    allow(Resolv).to receive(:getaddresses).and_return([ "100.64.0.7" ])
    allow(Socket).to receive(:tcp).and_raise(Errno::ETIMEDOUT)
    expect(doctor("https://comfy.example.com").steps.last.detail).to include("tailnet address")
  end

  it "passes when it answers" do
    allow(Resolv).to receive(:getaddresses).and_return([ "10.0.0.9" ])
    allow(Socket).to receive(:tcp).and_return(double(close: nil))
    expect(doctor("http://comfy.lan:8188")).to be_ok
  end
end
