# frozen_string_literal: true

# A rented GPU on RunPod, started for a training run and stopped after it
# (docs/HANDOFF.md "Training hosts"), through RunPod's REST API:
# POST /v1/pods/{id}/start and /stop. Its API key lives in the environment
# (RUNPOD_API_KEY) and nowhere else; the pod's id in config/comfy.yml
# `training_host.runpod_pod_id`. The pod runs ComfyUI with the training
# nodes and the base models; baible reaches it at TRAINING_COMFY_URL (for
# RunPod's proxy, https://<pod id>-8188.proxy.runpod.net).
module RunPod
  class Error < StandardError; end
  class Unreachable < Error; include Remote::Unreachable; end

  API = "https://rest.runpod.io/v1"

  module_function

  def pod_id = Comfy.training_host[:runpod_pod_id].presence

  def enabled? = pod_id.present? && ENV["RUNPOD_API_KEY"].present?

  def start!(http: nil) = post("start", http)

  def stop!(http: nil) = post("stop", http)

  def post(action, http)
    connection = Remote::Connection.new(service: RunPod, name: "RunPod", url: API, token: ENV.fetch("RUNPOD_API_KEY", ""), http: http)
    connection.post_json("/pods/#{ERB::Util.url_encode(pod_id)}/#{action}", {})
    true
  end
end
