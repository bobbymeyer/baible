# frozen_string_literal: true

# Rewrites the subject layer of an image prompt with a language model
# (config/llm.yml), in the way the image model reads best: booru tags for
# the anime families, plain sentences for the rest (Comfy::Family
# #prompt_style). Only the subject is rewritten: the house style, the
# framing, the entry's look (the same words in every picture of it) and the
# family's quality words stay as the author wrote them, and
# the model is told about them so it doesn't repeat or contradict them.
#
# Answers are remembered, so the same subject asked again gets the same words
# (and an image model that caches its text encodings can reuse them).
module PromptWriter
  STYLES = {
    "tags" => "Write comma-separated Danbooru-style tags, lowercase, most important first, 6 to 20 tags: " \
              "the kind of subject, count (1girl, 1boy, solo, no humans), colours, clothing, what it holds, pose, expression.",
    "prose" => "Write one or two plain sentences that describe only what can be seen: what the subject is, " \
               "its colours, build, clothing, what it holds, its pose and expression."
  }.freeze

  module_function

  # The subject rewritten, or nil when there is nothing to rewrite with.
  # Raises Llm::Error when the language model can't be reached.
  def write(parts, family:, client: Llm.client)
    subject = parts["subject"].to_s.strip
    return nil if subject.empty?

    style = STYLES.key?(family.prompt_style) ? family.prompt_style : "prose"
    system = <<~TEXT.squish
      You write the subject part of a prompt for an image generator.
      #{STYLES.fetch(style)}
      Leave out art style, medium, camera, framing, lighting, background and quality words: those are added separately.
      Never name real artists or real people. Keep any names the subject gives only if they help describe it.
      Reply with the prompt text alone, on one line, with nothing before or after it.
    TEXT
    user = <<~TEXT
      The subject to draw: #{subject}
      Already in the prompt, don't repeat or contradict: #{[ parts['style'], parts['framing'], parts['entry'], parts['detail'] ].map(&:to_s).reject(&:blank?).join(' | ').presence || 'nothing'}
    TEXT
    key = [ "prompt_writer", style, Digest::SHA256.hexdigest([ system, user, Llm.config[:model] ].join("\n")) ].join("/")
    Rails.cache.fetch(key, expires_in: 30.days) { tidy(client.chat(system: system, user: user)) }
  end

  # One line, no quotes or a leading label the model added anyway.
  def tidy(text)
    line = text.to_s.lines.map(&:strip).reject(&:empty?).first.to_s
    line.sub(/\A(prompt|tags|subject)\s*:\s*/i, "").delete_prefix('"').delete_suffix('"').strip.delete_suffix(".").strip
  end

  # The recipe with its subject rewritten and the prompt put back together,
  # or unchanged (with the reason) when the language model can't help.
  def rewrite(recipe, client: Llm.client)
    parts = recipe["parts"] or return recipe
    family = Comfy::Family.new(recipe["family"], recipe["model"])
    written = write(parts, family: family, client: client)
    return recipe unless written.present?

    recipe.merge("positive" => ArtDirection.compose(parts.merge("subject" => written)),
                 "parts" => parts.merge("written" => written))
  rescue Llm::Error => e
    recipe.merge("writer_error" => e.message)
  end
end
