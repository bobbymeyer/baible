# frozen_string_literal: true

require "socket"
require "resolv"

# Why the app can't see a service it should (ComfyUI or the language
# model): each step of reaching it in turn,
# stopping at the first that fails, with what that failure usually means.
# Run from the Settings page ("Check the connection"), or
# `bin/rails services:check` inside the app's container.
#
# Never shows a token, a header's value or a password.
class ConnectionCheck
  Step = Data.define(:ok, :label, :detail)

  def self.in_container?
    File.exist?("/.dockerenv") || File.exist?("/run/.containerenv")
  end

  def initialize(url:, name:, probe:, headers: [], token: false)
    @url = url.to_s
    @name = name
    @probe = probe # ->() { detail string } raising on failure
    @headers = headers
    @token = token
  end

  def self.comfy
    headers = (JSON.parse(Comfy.config[:headers].presence || "{}").keys rescue [])
    new(url: Comfy.config[:url], name: "ComfyUI", token: Comfy.config[:token].present?, headers: headers, probe: lambda {
      client = Comfy.client(timeout: 10)
      client.send(:get_json, "/system_stats")
      caps = client.capabilities
      raise Comfy::Error, caps.error unless caps.reachable?

      removal = caps.node?(Cutout.node) ? "backgrounds come off with #{Cutout.node} (#{Cutout.model})" : "no #{Cutout.node} to take backgrounds off: install ComfyUI-RMBG"
      "answers. #{caps.models.size} models, #{caps.loras.size} LoRAs; #{removal}."
    })
  end

  def self.llm
    return nil unless Llm.enabled?

    new(url: Llm.config[:url], name: "The language model", token: Llm.config[:token].present?, probe: lambda {
      client = Llm.client
      "answers: “#{client.chat(system: 'Reply with the word ready.', user: 'Ready?', max_tokens: 20).truncate(40)}”"
    })
  end

  def steps
    @steps ||= run
  end

  def ok? = steps.all?(&:ok)

  private

  def run
    steps = []
    uri = URI(@url) rescue nil
    return [ Step.new(false, "Address", "#{@url.inspect} isn't a URL") ] unless uri&.host

    shown = @url.sub(%r{//[^@/]*@}, "//")
    steps << Step.new(true, "Address", "#{shown}#{' (basic auth in the URL)' if uri.user}#{' · bearer token set' if @token}#{" · headers: #{@headers.join(', ')}" if @headers.any?}")
    if self.class.in_container? && %w[127.0.0.1 localhost ::1].include?(uri.host)
      return steps << Step.new(false, "Where", "The app is in a container, where #{uri.host} is the container itself, not the machine #{@name} runs on. " \
                                              "Use http://host.docker.internal:#{uri.port} (with extra_hosts: host.docker.internal:host-gateway), or #{@name}'s LAN or tailnet address.")
    end

    addresses = begin
      Resolv.getaddresses(uri.host).presence || Addrinfo.getaddrinfo(uri.host, nil).map(&:ip_address).uniq
    rescue SocketError
      []
    end
    if addresses.empty?
      hint = if uri.host == "host.docker.internal"
        "Add extra_hosts: [\"host.docker.internal:host-gateway\"] to the app's service in compose (Linux needs it; Docker Desktop and OrbStack provide it)."
      elsif uri.host.end_with?(".ts.net") || !uri.host.include?(".")
        "A tailnet (MagicDNS) name only resolves where Tailscale's DNS is used; containers usually don't. Use a public DNS name for it, or its 100.x address."
      else
        "The name doesn't resolve from here."
      end
      return steps << Step.new(false, "Name", "#{uri.host} doesn't resolve. #{hint}")
    end
    steps << Step.new(true, "Name", "#{uri.host} is #{addresses.first(3).join(', ')}")

    address = addresses.first
    begin
      Socket.tcp(address, uri.port, connect_timeout: 4).close
      steps << Step.new(true, "Connection", "port #{uri.port} is open")
    rescue Errno::ECONNREFUSED
      hint = if %w[127.0.0.1 ::1].include?(address)
        "Nothing is listening on port #{uri.port} here: is #{@name} running on this machine?"
      else
        "Nothing that the app can reach listens there. #{@name} listening only on 127.0.0.1 is the usual cause: " \
          "start it listening wider (ComfyUI: --listen), or go through the proxy that serves it (Caddy on the tailnet)."
      end
      return steps << Step.new(false, "Connection", "#{address}:#{uri.port} refused. #{hint}")
    rescue Errno::ETIMEDOUT, Errno::EHOSTUNREACH, Errno::ENETUNREACH, IO::TimeoutError, SocketError => e
      tailnet = address.start_with?("100.")
      return steps << Step.new(false, "Connection", "no route to #{address}:#{uri.port} (#{e.class.name.demodulize}). " \
                                                    "#{tailnet ? 'That is a tailnet address, and this container isn\'t on the tailnet: run Tailscale on the host with the container able to route through it, add a Tailscale sidecar, or use host.docker.internal instead.' : 'A firewall, or the wrong address.'}")
    end

    begin
      steps << Step.new(true, "Answer", "#{@name} #{@probe.call}")
    rescue Comfy::Error, Llm::Error, OpenSSL::SSL::SSLError => e
      steps << Step.new(false, "Answer", "#{e.message}#{' · the certificate for this name isn\'t trusted from here' if e.is_a?(OpenSSL::SSL::SSLError)}")
    end
    steps
  end
end
