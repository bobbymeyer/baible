# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Writing prompts with a language model" do
  # A language model that answers from a script and remembers what it was asked.
  class FakeLlm
    attr_reader :asked

    def initialize(*replies) = (@replies = replies) && (@asked = [])

    def chat(system:, user:)
      @asked << { system: system, user: user }
      reply = @replies.shift
      reply.is_a?(Exception) ? raise(reply) : reply
    end
  end

  describe Llm::Client do
    # One canned HTTP answer; keeps the request it got.
    class OneAnswer
      attr_reader :last

      def initialize(status, body) = (@status = status) && (@body = body)

      def request(req)
        @last = req
        Net::HTTPResponse::CODE_TO_OBJ.fetch(@status.to_s).new("1.1", @status.to_s, "").tap do |response|
          response.instance_variable_set(:@body, JSON.generate(@body))
          response.instance_variable_set(:@read, true)
        end
      end
    end

    it "asks any OpenAI-compatible server, and leaves a reasoning model's thinking out of the reply" do
      http = OneAnswer.new(200, { "choices" => [ { "message" => { "content" => "<think>hmm</think>\n1boy, goblin, green skin" } } ] })
      llm = described_class.new(url: "http://llm.test:8090/v1", model: "qwen3", token: "tok", headers: "{}", timeout: 5, http: http)
      expect(llm.chat(system: "s", user: "u")).to eq("1boy, goblin, green skin")
      expect(http.last.path).to eq("/v1/chat/completions")
      expect(http.last["Authorization"]).to eq("Bearer tok")
      expect(JSON.parse(http.last.body)).to include("model" => "qwen3", "messages" => [ { "role" => "system", "content" => "s" }, { "role" => "user", "content" => "u" } ])
    end

    it "explains a refusal" do
      http = OneAnswer.new(404, { "error" => { "message" => "model not found" } })
      llm = described_class.new(url: "http://llm.test/v1", model: "", token: "", headers: "{}", timeout: 5, http: http)
      expect { llm.chat(system: "s", user: "u") }.to raise_error(Llm::Error, "The language model answered 404: model not found")
    end
  end

  describe "reading JSON from a model's reply" do
    it "takes the first object, whatever is around it" do
      expect(Llm.parse_json("Sure!\n```json\n{\"a\": \"x } y\", \"b\": [{\"c\": 2}]}\n```\nHope that helps.")).to eq("a" => "x } y", "b" => [ { "c" => 2 } ])
      expect(Llm.parse_json("no json here")).to be_nil
      expect(Llm.parse_json("{broken")).to be_nil
    end
  end

  describe PromptWriter do
    let(:parts) { { "prefix" => "masterpiece, best quality", "style" => "ink wash", "framing" => "profile view", "subject" => "Goblin, a small green raider", "detail" => "" } }
    let(:recipe) { { "model" => "anima-preview.safetensors", "family" => "anima", "parts" => parts, "positive" => ArtDirection.compose(parts) } }

    it "rewrites only the subject, in the family's style, and puts the prompt back together" do
      llm = FakeLlm.new("Tags: goblin, green skin, holding dagger, cape.")
      written = described_class.rewrite(recipe, client: llm)
      expect(written["positive"]).to eq("masterpiece, best quality, ink wash, profile view, goblin, green skin, holding dagger, cape")
      expect(written.dig("parts", "written")).to eq("goblin, green skin, holding dagger, cape")
      expect(llm.asked.sole[:system]).to include("Danbooru-style tags")
      expect(llm.asked.sole[:user]).to include("Goblin, a small green raider", "ink wash | profile view")

      prose = FakeLlm.new("A small green goblin in a tattered cape.")
      described_class.rewrite(recipe.merge("model" => "krea2_turbo.safetensors", "family" => "krea2"), client: prose)
      expect(prose.asked.sole[:system]).to include("plain sentences")
    end

    it "keeps the prompt as written when the language model can't help" do
      written = described_class.rewrite(recipe, client: FakeLlm.new(Llm::Error.new("The language model isn't reachable")))
      expect(written["positive"]).to eq(recipe["positive"])
      expect(written["writer_error"]).to eq("The language model isn't reachable")
    end
  end

  describe "in a batch" do
    include ActiveJob::TestHelper

    let(:goblin) { make_subject(make_project, "Creature", "Goblin") }

    it "writes the subject once, before anything is queued, and every candidate shares it" do
      allow(Llm).to receive(:enabled?).and_return(true)
      batch = Batch.start!(goblin, count: 2)
      comfy = FakeComfy.new
      llm = FakeLlm.new("goblin, green skin, rusty knife")
      BatchJob.new.perform(batch.reload, client: comfy, llm: llm)
      texts = comfy.submitted.map { |g| g.values.find { |n| n["class_type"] == "CLIPTextEncode" }["inputs"]["text"] }
      expect(texts.uniq).to eq([ batch.reload.recipe["positive"] ])
      expect(texts.first).to end_with("goblin, green skin, rusty knife")
      expect(llm.asked.size).to eq(1)
      expect(batch.recipe["workflow"]).to start_with("UNETLoader → CLIPLoader")
    end

    it "doesn't ask when the author said not to" do
      allow(Llm).to receive(:enabled?).and_return(true)
      batch = Batch.start!(goblin, count: 1, write: false)
      llm = FakeLlm.new
      BatchJob.new.perform(batch.reload, client: FakeComfy.new, llm: llm)
      expect(llm.asked).to be_empty
    end
  end
end
