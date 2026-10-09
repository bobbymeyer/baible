# frozen_string_literal: true

# The morning summary (docs/HANDOFF.md "The morning summary"): one a night,
# written at the first tick after the window closes, of what that night did:
# what was made and failed, what waits for review, training runs, the
# standing orders' reports, and what wasn't reached. Kept for the Overnight
# page, and
# sent to MORNING_WEBHOOK_URL when it's set (Webhook), so it reaches a phone
# rather than waiting to be looked at. A send that fails is kept with its
# reason; it is not retried.
class NightSummary < ApplicationRecord
  scope :newest_first, -> { order(closed_at: :desc) }

  def self.write!(opened, closed)
    payload = gather(opened, closed)
    summary = create!(opened_at: opened, closed_at: closed, payload: payload, text: words(payload))
    summary.deliver!
    summary
  end

  # The night in figures, from the records: batches the night shift let go
  # in the window, runs that ended in it (or are still going), orders
  # planned in it.
  def self.gather(opened, closed)
    window = opened..closed
    batches = Batch.where(night: true, released_at: window).includes(:candidates, :variant, subject: :project)
    candidates = batches.flat_map(&:candidates)
    runs = Training.where(updated_at: window).or(Training.where(status: %w[queued waiting running])).includes(:entry)
    {
      "night" => { "opened_at" => opened.utc.iso8601, "closed_at" => closed.utc.iso8601 },
      "batches" => { "made" => batches.count { |b| b.status == "done" }, "failed" => batches.count { |b| b.status == "failed" },
                     "still_running" => batches.count { |b| b.status.in?(%w[queued waiting running]) },
                     "candidates" => candidates.count { |c| c.status == "done" } },
      "to_review" => batches.select { |b| b.status == "done" }.group_by { |b| b.subject.project.name }
                            .transform_values { |rows| rows.map(&:title) },
      "failures" => batches.select { |b| b.status == "failed" }.map { |b| "#{b.title}: #{b.error}" },
      "not_reached" => Batch.where(status: "scheduled").count + Training.where(status: "scheduled").count,
      "training" => runs.filter_map do |run|
        next unless run.status.in?(%w[done failed queued waiting running])

        { "run" => run.title, "status" => run.status, "lora" => run.lora, "error" => run.error }
      end,
      "orders" => StandingOrder.where(planned_at: window).includes(:project, :kind, :entry).map { |o| "#{o.label}, #{o.where}: #{o.report}" },
      "url" => (ENV["APP_URL"].present? ? "#{ENV['APP_URL'].chomp('/')}/night" : nil)
    }
  end

  # The summary as a few plain lines, what was made first.
  def self.words(p)
    lines = []
    b = p["batches"]
    batches = b["made"] + b["failed"] + b["still_running"]
    if batches.zero? && p["training"].empty?
      lines << "Nothing ran last night."
    elsif batches.positive?
      made = "#{b['made']} #{b['made'] == 1 ? 'batch' : 'batches'} made (#{b['candidates']} candidates)"
      made += ", #{b['failed']} failed" if b["failed"].positive?
      made += ", #{b['still_running']} still going" if b["still_running"].positive?
      lines << made + "."
    end
    p["to_review"].each { |project, titles| lines << "To review in #{project}: #{titles.first(8).join('; ')}#{" and #{titles.size - 8} more" if titles.size > 8}." }
    p["failures"].first(5).each { |line| lines << "Failed: #{line}" }
    p["training"].each do |run|
      lines << case run["status"]
      when "done" then "Trained #{run['run']}: #{run['lora']}."
      when "failed" then "Training #{run['run']} failed: #{run['error']}"
      else "Training #{run['run']} is still going."
      end
    end
    lines << "Not reached, still queued: #{p['not_reached']}." if p["not_reached"].positive?
    p["orders"].each { |line| lines << "Standing order: #{line}" }
    lines << p["url"] if p["url"]
    lines.join("\n")
  end

  def deliver!
    return unless Webhook.enabled?

    Webhook.deliver(text, payload.merge("title" => title))
    update!(sent_at: Time.current, error: nil)
  rescue Webhook::Error => e
    update!(error: e.message.truncate(500))
  end

  def title = "baible: #{heading.downcase_first}"

  def heading = "Last night (#{closed_at.to_date.to_fs(:long)})"
end
