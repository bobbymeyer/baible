# frozen_string_literal: true

# Request specs read the page they got back as a document.
module RequestPages
  # The last response, parsed (Nokogiri). Rails parses an HTML response
  # itself; a fragment is parsed here.
  def page
    body = response.parsed_body
    body.is_a?(Nokogiri::XML::Node) ? body : Nokogiri::HTML5.fragment(body.to_s)
  end
end

RSpec.configure do |config|
  config.include RequestPages, type: :request
end
