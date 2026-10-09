# frozen_string_literal: true

require "rails_helper"

RSpec.describe Llm::Client do
  let(:reply) { { "choices" => [ { "message" => { "content" => "goblin, green skin" } } ] } }

  def client(http, **options) = described_class.new(url: "http://llm.test/v1", model: "qwen-moe", http: http, **options)

  it "sends what LLM_EXTRA_BODY adds with every request, under the fields it sets itself" do
    http = FakeHttp.new("/v1/chat/completions" => [ 200, reply ])
    extra = '{"chat_template_kwargs":{"enable_thinking":false},"model":"not this one"}'
    expect(client(http, extra_body: extra).chat(system: "s", user: "u")).to eq("goblin, green skin")
    body = JSON.parse(http.requests.sole.body)
    expect(body).to include("chat_template_kwargs" => { "enable_thinking" => false }, "model" => "qwen-moe", "max_tokens" => 400)
  end

  it "sends nothing extra by default, and says so when LLM_EXTRA_BODY isn't a JSON object" do
    http = FakeHttp.new("/v1/chat/completions" => [ 200, reply ])
    client(http, extra_body: "").chat(system: "s", user: "u")
    expect(JSON.parse(http.requests.sole.body).keys).to contain_exactly("messages", "temperature", "max_tokens", "stream", "model")

    expect { client(http, extra_body: "{nope") }.to raise_error(Llm::Error, "LLM_EXTRA_BODY isn't valid JSON")
    expect { client(http, extra_body: "[1]") }.to raise_error(Llm::Error, "LLM_EXTRA_BODY must be a JSON object")
  end
end
