# frozen_string_literal: true

require "rails_helper"

RSpec.describe "The app's settings (SiteSetting)", type: :request do
  it "says where ComfyUI and the language model are, over the environment's" do
    get settings_path
    expect(response.body).to include("ComfyUI", "Language model", "Check the connection")
    expect(Comfy.config[:url]).to eq("http://comfy.test")
    expect(Llm).not_to be_enabled

    patch settings_path, params: { site_setting: { comfy_url: "http://host.docker.internal:8188", comfy_model: "anima-preview.safetensors",
                                                   music_model: "ace_step_v1_5.safetensors", rmbg_model: "BiRefNet-general",
                                                   llm_url: "http://host.docker.internal:8090/v1", llm_model: "qwen3" } }
    expect(response).to redirect_to(settings_path(check: 1, anchor: "connection"))
    expect(Comfy.config[:url]).to eq("http://host.docker.internal:8188")
    expect(Comfy.config[:families]).to be_present # the rest still from config
    expect(Comfy::Music.default_model).to eq("ace_step_v1_5.safetensors")
    expect(Comfy::Music.settings[:steps]).to eq(50)
    expect(Llm).to be_enabled
    expect(Llm.config[:model]).to eq("qwen3")
    expect(Cutout.model).to eq("BiRefNet-general")
    expect(Cutout.ground).to eq("green") # the rest still from config

    patch settings_path, params: { site_setting: { comfy_url: "", llm_url: "" } }
    expect(Comfy.config[:url]).to eq("http://comfy.test") # blank: back to the environment
    expect(Llm).not_to be_enabled
  end

  it "sets how rough drafts are, and how many candidates a batch makes" do
    patch settings_path, params: { site_setting: { draft_size: "384", draft_steps: "10", draft_denoise: "0.5", candidates: "2" } }
    expect(Comfy.config[:candidates]).to eq(2)
    family = Comfy::Family.for("anima-preview.safetensors")
    expect([ family.draft_size(1024, 1024), family.draft_steps, family.refine_denoise ]).to eq([ [ 384, 384 ], 10, 0.5 ])

    patch settings_path, params: { site_setting: { draft_size: "", draft_steps: "", draft_denoise: "", candidates: "" } }
    family = Comfy::Family.for("anima-preview.safetensors")
    expect([ family.draft_size(1024, 1024), family.draft_steps, family.refine_denoise ]).to eq([ [ 512, 512 ], 16, 0.6 ])

    patch settings_path, params: { site_setting: { draft_size: "5000" } }
    expect(response).to have_http_status(:unprocessable_content)
  end

  it "keeps passwords out of the database, and wants real addresses" do
    patch settings_path, params: { site_setting: { comfy_url: "http://me:s3cret@comfy.lan:8188" } }
    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("can&#39;t hold a user or password")
    patch settings_path, params: { site_setting: { llm_url: "ftp://nope" } }
    expect(response.body).to include("must be an http:// or https:// address")
    expect(SiteSetting.count).to eq(0)
  end

  it "is for people signed in", signed_out: true do
    get settings_path
    expect(response).to redirect_to(new_session_path)
    patch settings_path, params: { site_setting: { comfy_url: "http://evil.test" } }
    expect(SiteSetting.count).to eq(0)
  end

  it "checks the connection step by step, without showing secrets" do
    allow(ConnectionCheck).to receive(:in_container?).and_return(false)
    allow(Resolv).to receive(:getaddresses).and_return([ "10.0.0.9" ])
    allow(Socket).to receive(:tcp).and_raise(Errno::ECONNREFUSED)
    get settings_path(check: 1)
    expect(response.body).to include("Connection", "comfy.test", "refused")
  end
end
