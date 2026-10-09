# frozen_string_literal: true

require "net/http"

# Talking to the services the app leans on, over HTTP: ComfyUI (Comfy) and
# the language model (Llm). Each is somewhere else, and may be local, on a LAN or tailnet, or behind a proxy that wants
# a bearer token, basic auth (in the URL) or headers of its own.
#
# Each service has its own Error, and an Unreachable one for when nothing
# answered at all (asleep, restarting, off the network). Those all carry
# Remote::Unreachable, so a job can wait for any of them the same way
# (ApplicationJob.waits_for_services).
module Remote
  # Marks a service's "couldn't reach it": worth trying again later.
  module Unreachable; end

  NETWORK_ERRORS = [ SystemCallError, IOError, SocketError, Timeout::Error, OpenSSL::SSL::SSLError ].freeze

  # One service's address, credentials and timeouts, and requests to it.
  # service: the module whose Error and Unreachable it raises; name: what
  # to call it in a message ("ComfyUI"); rejection: what to make of a
  # response that isn't a success, if the service explains itself.
  class Connection
    # The address, without any credentials in it: safe to show.
    attr_reader :base

    def initialize(service:, name:, url:, token: nil, headers: nil, headers_setting: "headers", timeout: 30, open_timeout: 5,
                   rejection: nil, http: nil)
      @service = service
      @name = name
      @rejection = rejection
      given = URI(url.to_s.chomp("/"))
      @user = given.user && URI.decode_www_form_component(given.user)
      @password = given.password && URI.decode_www_form_component(given.password)
      @base = URI(given.to_s.sub(%r{//[^@/]*@}, "//"))
      @headers = parse_headers(headers, headers_setting)
      @headers["Authorization"] = "Bearer #{token}" if token.present?
      @timeout = timeout.to_i.positive? ? timeout.to_i : 30
      @open_timeout = [ @timeout, open_timeout ].min
      @http = http
      @injected = !http.nil?
    end

    def get(path) = request(Net::HTTP::Get.new(path(path), @headers))

    def post_json(path, payload)
      req = Net::HTTP::Post.new(path(path), @headers.merge("Content-Type" => "application/json"))
      req.body = JSON.generate(payload)
      request(req)
    end

    # A plain body of the given type (a webhook taking text).
    def post_body(path, body, content_type)
      req = Net::HTTP::Post.new(path(path), @headers.merge("Content-Type" => content_type))
      req.body = body.to_s
      request(req)
    end

    # A multipart form: [[name, value], [name, io, { filename:, content_type: }]].
    def post_form(path, fields)
      req = Net::HTTP::Post.new(path(path), @headers)
      req.set_form(fields, "multipart/form-data")
      request(req)
    end

    # The response when it succeeds. Otherwise the service's Error, with
    # its own explanation (or the status), or its Unreachable when nothing
    # answered.
    def request(req)
      req.basic_auth(@user, @password.to_s) if @user
      response = (@http || connection).request(req)
      return response if response.is_a?(Net::HTTPSuccess)

      raise @service::Error, @rejection&.call(response) || "#{@name} answered #{response.code}"
    rescue *NETWORK_ERRORS => e
      raise @service::Unreachable, unreachable(e)
    end

    def json(response)
      JSON.parse(response.body.to_s)
    rescue JSON::ParserError
      raise @service::Error, "#{@name} sent something that isn't JSON"
    end

    # One connection for a run of requests, when the connection is ours.
    def session
      return yield if @http

      @http = connection
      @http.start { yield }
    ensure
      @http = nil unless @injected
    end

    def unreachable(error)
      "#{@name} isn't reachable at #{@base} (#{error.class.name.demodulize}: #{error.message})"
    end

    private

    # The base's path and the request's; the base's query too, when the
    # request is to the base itself (a webhook URL carrying its own).
    def path(path)
      full = "#{@base.path}#{path}".presence || "/"
      path.empty? && @base.query ? "#{full}?#{@base.query}" : full
    end

    def parse_headers(headers, setting)
      value = headers.is_a?(String) ? (headers.strip.empty? ? {} : JSON.parse(headers)) : headers.to_h
      value.to_h.transform_keys(&:to_s).transform_values(&:to_s)
    rescue JSON::ParserError
      raise @service::Error, "#{setting} isn't a JSON object"
    end

    def connection
      Net::HTTP.new(@base.host, @base.port).tap do |http|
        http.use_ssl = @base.scheme == "https"
        http.open_timeout = @open_timeout
        http.read_timeout = @timeout
      end
    end
  end
end
