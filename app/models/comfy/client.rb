# frozen_string_literal: true

# ComfyUI over the network, through its plain HTTP API: queue a prompt (a
# workflow graph), ask its history whether it has finished, download the
# images it saved, and ask what it has installed. It assumes nothing about
# the machine: ComfyUI can be local, on a LAN or tailnet, or behind a proxy
# that wants a bearer token, basic auth (in the URL) or its own headers.
#
# This is the backend interface the pipeline uses; anything answering the
# same four calls can stand in for it (spec/support/fake_comfy.rb does):
#   submit(graph) → prompt id      result(prompt id) → nil or [image]
#   fetch(image)  → bytes          capabilities      → Comfy::Capabilities
#   upload(bytes, name, subfolder:, content_type:) → the name ComfyUI keeps it under
#   run_seconds(prompt id) → how long ComfyUI spent on it, once finished
module Comfy
  class Client
    def initialize(url: Comfy.config[:url], token: Comfy.config[:token], headers: Comfy.config[:headers], http: nil, timeout: 30)
      @remote = Remote::Connection.new(service: Comfy, name: "ComfyUI", url: url, token: token, headers: headers,
                                       headers_setting: "COMFY_HEADERS", timeout: timeout, rejection: method(:rejection), http: http)
    end

    # The address, without any credentials in it: safe to show.
    def base = @remote.base

    # Queue a graph. Returns ComfyUI's prompt id.
    def submit(graph, client_id: SecureRandom.uuid)
      body = parse(@remote.post_json("/prompt", { prompt: graph, client_id: client_id }))
      body.fetch("prompt_id") { raise Error, "ComfyUI didn't return a prompt id" }
    end

    # nil while the prompt is queued or running; otherwise the images (or
    # audio) its output nodes saved, as [{ "filename", "subfolder", "type" }].
    def result(prompt_id)
      entry = get_json("/history/#{prompt_id}")[prompt_id]
      return nil unless entry

      (@entries ||= {})[prompt_id] = entry

      status = entry["status"] || {}
      if status["status_str"] == "error"
        raise Error, execution_error(status) || "ComfyUI failed to run the workflow"
      end
      return nil if status.key?("completed") && !status["completed"]

      entry.fetch("outputs", {}).values.flat_map { |output| Array(output["images"]) + Array(output["audio"]) }.reject { |file| file["type"] == "temp" }
    end

    # Seconds from ComfyUI starting a prompt to finishing it, from the
    # timestamps in its history (after #result has seen it finish).
    def run_seconds(prompt_id)
      messages = Array(@entries&.dig(prompt_id, "status", "messages"))
      started = messages.find { |kind, _| kind == "execution_start" }&.last&.dig("timestamp")
      ended = messages.find { |kind, _| %w[execution_success execution_error].include?(kind) }&.last&.dig("timestamp")
      ((ended - started) / 1000.0).round(1) if started && ended
    end

    # Put an image in ComfyUI's input folder, for a LoadImage node to start
    # from, or a file in a subfolder of it (a training set's pictures and
    # their captions: ComfyUI stores what it is sent). Returns the name to
    # give LoadImage.
    def upload(bytes, name, subfolder: nil, content_type: "image/png")
      fields = [ [ "overwrite", "true" ], [ "type", "input" ] ]
      fields << [ "subfolder", subfolder ] if subfolder
      fields << [ "image", StringIO.new(bytes.to_s.b), { filename: name, content_type: content_type } ]
      answer = parse(@remote.post_form("/upload/image", fields))
      [ answer["subfolder"].presence, answer.fetch("name") { raise Error, "ComfyUI didn't take the image" } ].compact.join("/")
    end

    # The bytes of one saved image (or audio file).
    def fetch(image)
      query = URI.encode_www_form(filename: image["filename"], subfolder: image["subfolder"].to_s, type: image["type"] || "output")
      @remote.get("/view?#{query}").body
    end

    # What this ComfyUI has installed. Each node is asked about on its own
    # (a full /object_info can run to megabytes); a node it doesn't have
    # answers empty.
    def capabilities
      info = @remote.session do
        Capabilities::NODES.each_with_object({}) do |node, found|
          definition = get_json("/object_info/#{ERB::Util.url_encode(node)}")[node]
          found[node] = definition if definition
        end
      end
      Capabilities.new(info)
    rescue Unreachable => e
      Capabilities.unreachable(e.message, offline: true)
    rescue Error => e
      Capabilities.unreachable(e.message)
    rescue *Remote::NETWORK_ERRORS => e # starting the session
      Capabilities.unreachable(@remote.unreachable(e), offline: true)
    end

    def reachable?
      get_json("/system_stats")
      true
    rescue Error
      false
    end

    private

    def get_json(path) = parse(@remote.get(path))

    def parse(response) = @remote.json(response)

    def execution_error(status)
      message = Array(status["messages"]).find { |kind, _| kind == "execution_error" }&.last
      message && [ message["node_type"], message["exception_message"] ].compact.join(": ").strip.presence
    end

    # ComfyUI explains a rejected graph in "error" and per-node "node_errors".
    def rejection(response)
      body = JSON.parse(response.body.to_s) rescue {}
      nodes = (body["node_errors"] || {}).values.flat_map do |node|
        Array(node["errors"]).map { |e| "#{node['class_type']}: #{e['details'].presence || e['message']}" }
      end
      [ body.dig("error", "message") || "ComfyUI answered #{response.code}", *nodes ].join(" · ")
    end
  end
end
