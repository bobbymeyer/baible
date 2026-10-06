# frozen_string_literal: true

require "rails_helper"

RSpec.describe Comfy::Client do
  def client(routes) = described_class.new(url: "http://comfy.test", http: FakeHttp.new(routes))

  it "queues a graph and returns ComfyUI's prompt id" do
    http = FakeHttp.new("/prompt" => [ 200, { "prompt_id" => "abc" } ])
    expect(described_class.new(url: "http://comfy.test", http: http).submit({ "1" => {} }, client_id: "me")).to eq("abc")
    expect(JSON.parse(http.requests.sole.body)).to eq("prompt" => { "1" => {} }, "client_id" => "me")
  end

  it "explains a rejected graph with ComfyUI's node errors" do
    rejected = { "error" => { "message" => "Prompt outputs failed validation" },
                 "node_errors" => { "2" => { "class_type" => "LoraLoader", "errors" => [ { "message" => "Value not in list", "details" => "lora_name: 'nope' not in []" } ] } } }
    expect { client("/prompt" => [ 400, rejected ]).submit({}) }
      .to raise_error(Comfy::Error, "Prompt outputs failed validation · LoraLoader: lora_name: 'nope' not in []")
  end

  it "reads history: nothing yet, then the saved images" do
    expect(client("/history/abc" => [ 200, {} ]).result("abc")).to be_nil
    done = { "abc" => { "status" => { "status_str" => "success", "completed" => true },
                        "outputs" => { "9" => { "images" => [ { "filename" => "g_00001_.png", "subfolder" => "baible", "type" => "output" } ] } } } }
    expect(client("/history/abc" => [ 200, done ]).result("abc")).to eq([ { "filename" => "g_00001_.png", "subfolder" => "baible", "type" => "output" } ])
  end

  it "raises the execution error when a run failed" do
    failed = { "abc" => { "status" => { "status_str" => "error", "completed" => false,
                                        "messages" => [ [ "execution_error", { "node_type" => "KSampler", "exception_message" => "out of memory" } ] ] } } }
    expect { client("/history/abc" => [ 200, failed ]).result("abc") }.to raise_error(Comfy::Error, "KSampler: out of memory")
  end

  it "downloads an image through /view" do
    http = FakeHttp.new("/view" => [ 200, "PNGBYTES" ])
    bytes = described_class.new(url: "http://comfy.test", http: http).fetch("filename" => "a b.png", "subfolder" => "baible", "type" => "output")
    expect(bytes).to eq("PNGBYTES")
    expect(http.requests.sole.path).to eq("/view?filename=a+b.png&subfolder=baible&type=output")
  end

  it "reads what's installed node by node, in either of ComfyUI's ways of listing choices" do
    routes = {
      "/object_info/UNETLoader" => [ 200, { "UNETLoader" => { "input" => { "required" => { "unet_name" => [ [ "anima-preview.safetensors" ], {} ] } } } } ],
      "/object_info/CLIPLoader" => [ 200, { "CLIPLoader" => { "input" => { "required" => {
        "clip_name" => [ "COMBO", { "options" => [ "qwen_3_06b_base.safetensors" ] } ], "type" => [ [ "stable_diffusion", "anima" ] ]
      } } } } ]
    }
    asked = Comfy::Capabilities::NODES
    http = FakeHttp.new(asked.to_h { |node| [ "/object_info/#{ERB::Util.url_encode(node)}", [ 200, {} ] ] }.merge(routes))
    caps = described_class.new(url: "http://comfy.test", http: http).capabilities
    expect(caps).to be_reachable
    expect(caps.diffusion_models).to eq([ "anima-preview.safetensors" ])
    expect(caps.text_encoders).to eq([ "qwen_3_06b_base.safetensors" ])
    expect(caps.clip_types).to eq(%w[stable_diffusion anima])
    expect(caps.node?("UNETLoader")).to be(true)
    expect(caps.node?("CheckpointLoaderSimple")).to be(false)
    expect(caps.checkpoints).to eq([])
    expect(client({}).capabilities).not_to be_reachable
  end

  it "sends a bearer token and any headers a proxy wants, and basic auth from the URL without ever showing it" do
    http = FakeHttp.new("/api/prompt" => [ 200, { "prompt_id" => "abc" } ])
    comfy = described_class.new(url: "https://me:s3cret@comfy.example/api", token: "tok", headers: '{"CF-Access-Client-Id": "id"}', http: http)
    comfy.submit({})
    request = http.requests.sole
    expect(request.path).to eq("/api/prompt")
    expect(request["Authorization"]).to start_with("Basic ") # basic auth from the URL is applied last
    expect(request["CF-Access-Client-Id"]).to eq("id")
    expect(comfy.base.to_s).to eq("https://comfy.example/api")

    bearer = FakeHttp.new("/prompt" => [ 200, { "prompt_id" => "abc" } ])
    described_class.new(url: "http://comfy.test", token: "tok", http: bearer).submit({})
    expect(bearer.requests.sole["Authorization"]).to eq("Bearer tok")

    expect { described_class.new(url: "http://me:s3cret@comfy.test", http: FakeHttp.new({})).submit({}) }
      .to raise_error(Comfy::Error) { |e| expect(e.message).not_to include("s3cret") }
  end

  it "says where it tried when ComfyUI isn't there, as something worth trying again" do
    expect { client({}).submit({}) }.to raise_error(Comfy::Unreachable, /isn't reachable at http:\/\/comfy.test/)
    expect(client({})).not_to be_reachable
    expect(client({}).capabilities).to be_offline
    expect(client("/object_info/CheckpointLoaderSimple" => [ 500, { "error" => { "message" => "boom" } } ]).capabilities).not_to be_offline
  end
end
