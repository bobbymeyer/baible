# frozen_string_literal: true

# Answers requests from a table of path => [status, body], recording them.
class FakeHttp
  attr_reader :requests

  def initialize(routes) = (@routes = routes) && (@requests = [])

  def request(req)
    @requests << req
    status, body = @routes.fetch(req.path.split("?").first) { raise Errno::ECONNREFUSED }
    Net::HTTPResponse::CODE_TO_OBJ.fetch(status.to_s).new("1.1", status.to_s, "").tap do |response|
      response.instance_variable_set(:@body, body.is_a?(String) ? body : JSON.generate(body))
      response.instance_variable_set(:@read, true)
    end
  end
end
