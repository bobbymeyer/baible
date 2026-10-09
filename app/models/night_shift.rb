# frozen_string_literal: true

# Work queued for the night (docs/HANDOFF.md "Overnight"): batches and
# training runs wait as "scheduled" until the night window, then are let
# into ComfyUI one at a time, so that whatever someone starts by hand at
# night is never stuck behind the whole night's queue, and nothing new
# starts once the window has closed (what is running finishes).
#
# NightShiftJob ticks every minute. A tick lets the next item go only when
# the window is open, nothing of baible's is with ComfyUI (queued, waiting
# or running), and ComfyUI's own queue is empty (it may be busy with work
# from elsewhere). Generations go first, oldest first; training runs, which
# take hours, after them.
module NightShift
  Window = Data.define(:start, :finish, :zone) do
    # Whether the window is open at a moment. A window may cross midnight.
    def open?(at = Time.current)
      now = minutes(at.in_time_zone(zone))
      from = minutes(start)
      to = minutes(finish)
      from <= to ? now >= from && now < to : now >= from || now < to
    end

    # When it next opens (now, if it's open).
    def opens_at(at = Time.current)
      return at if open?(at)

      local = at.in_time_zone(zone)
      hour, minute = start.split(":").map(&:to_i)
      candidate = local.change(hour: hour, min: minute)
      candidate += 1.day if candidate <= local
      candidate
    end

    def label = "#{start} to #{finish}, #{zone.name}"

    private

    def minutes(time)
      time = time.strftime("%H:%M") unless time.is_a?(String)
      hour, minute = time.split(":").map(&:to_i)
      hour * 60 + minute
    end
  end

  module_function

  # config/comfy.yml `night`, with the Settings page over it.
  def window
    night = Comfy.config.fetch(:night, {}).to_h.symbolize_keys
    zone = ActiveSupport::TimeZone[night[:zone].to_s] || ActiveSupport::TimeZone["UTC"]
    Window.new(start: night.fetch(:start, "23:00").to_s, finish: night.fetch(:end, "07:00").to_s, zone: zone)
  end

  def queued_batches = Batch.where(status: "scheduled").order(:id)
  def queued_trainings = Training.where(status: "scheduled").order(:updated_at, :id)

  # Anything of baible's with ComfyUI, or on its way.
  def busy?
    Batch.where(status: %w[queued waiting running]).exists? || Training.where(status: %w[queued waiting running]).exists?
  end

  # One tick: let the next scheduled thing go, when it may. Returns what was
  # let go, or why nothing was (a symbol), for the log and the specs.
  def tick!(client: Comfy.client, at: Time.current)
    return :closed unless window.open?(at)

    batch = queued_batches.first
    training = queued_trainings.first unless batch
    return :nothing_queued unless batch || training
    return :busy if busy?
    return :comfy_busy unless client.queue_size.zero?

    batch ? batch.release! : training.train!
    batch || training
  rescue Comfy::Error => e
    Rails.logger.info("[night shift] ComfyUI isn't answering: #{e.message}")
    :comfy_unreachable
  end
end
