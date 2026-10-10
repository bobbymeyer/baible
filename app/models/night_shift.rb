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
# take hours, after them. A run for the training host (a rented GPU) goes on
# its own track, as soon as the host is free. The first tick of each night
# plans the standing orders' share (StandingOrder), queued after what was queued by hand; the
# first after the window closes writes the morning summary (NightSummary).
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

    # When the window that is open now opened, or nil when it's closed.
    def opened_at(at = Time.current)
      return unless open?(at)

      local = at.in_time_zone(zone)
      hour, minute = start.split(":").map(&:to_i)
      opened = local.change(hour: hour, min: minute)
      opened > local ? opened - 1.day : opened
    end

    # When the window last closed, and when that night's window had opened:
    # [opened, closed], or nil while it's open.
    def last_night(at = Time.current)
      return if open?(at)

      local = at.in_time_zone(zone)
      hour, minute = finish.split(":").map(&:to_i)
      closed = local.change(hour: hour, min: minute)
      closed -= 1.day if closed > local
      length = (minutes(finish) - minutes(start)) % (24 * 60)
      [ closed - length.minutes, closed ]
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

  # The standing orders' share of tonight, once a night window (each order
  # remembers when it last planned).
  def plan!(at = Time.current)
    opened = window.opened_at(at) or return
    StandingOrder.enabled.includes(:project, :kind, :entry).find_each { |order| order.plan!(opened) }
  end

  def queued_batches = Batch.where(status: "scheduled").order(:id)
  def queued_trainings = Training.where(status: "scheduled").order(:updated_at, :id)

  # Anything of baible's with this ComfyUI, or on its way (a run on the
  # training host doesn't count).
  def busy?
    Batch.where(status: %w[queued waiting running]).exists? ||
      Training.where(host: "local", status: %w[queued waiting running]).exists?
  end

  # One tick: let the next scheduled thing go, when it may. Returns what was
  # let go, or why nothing was (a symbol), for the log and the specs.
  def tick!(client: Comfy.client, at: Time.current)
    unless window.open?(at)
      summarize!(at)
      return :closed
    end

    plan!(at)
    remote = release_remote!
    local = release_local!(client)
    local.is_a?(Symbol) && remote ? remote : local
  end

  # The next local thing: generations, then runs that train here.
  def release_local!(client)
    batch = queued_batches.first
    training = queued_trainings.where(host: "local").first unless batch
    return :nothing_queued unless batch || training
    return :busy if busy?
    return :comfy_busy unless client.queue_size.zero?

    batch ? batch.release! : training.train!
    batch || training
  rescue Comfy::Error => e
    Rails.logger.info("[night shift] ComfyUI isn't answering: #{e.message}")
    :comfy_unreachable
  end

  # A run for the training host goes as soon as the host has nothing of
  # baible's: it doesn't wait for this ComfyUI, and this ComfyUI doesn't
  # wait for it.
  def release_remote!
    training = queued_trainings.where(host: "remote").first or return
    return if Training.where(host: "remote", status: %w[queued waiting running]).exists?

    training.train!
    training
  end

  # The morning summary of the night that last closed, once (NightSummary).
  def summarize!(at = Time.current)
    opened, closed = window.last_night(at)
    return unless closed
    return if NightSummary.exists?(closed_at: closed)

    NightSummary.write!(opened, closed)
  end
end
