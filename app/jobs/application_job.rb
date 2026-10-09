class ApplicationJob < ActiveJob::Base
  # Automatically retry jobs that encountered a deadlock
  # retry_on ActiveRecord::Deadlocked

  # Most jobs are safe to ignore if the underlying records are no longer available
  # discard_on ActiveJob::DeserializationError

  # A service the job needs that can't be reached (ComfyUI, the background
  # remover, the language model: Remote) is waited for rather than given up
  # on: tried again after 30 seconds, then twice as long each time up to
  # every 10 minutes, for about a day. Then the block hears of it, with the
  # job (its arguments) and the last error.
  SERVICE_RETRY_FIRST = 30.seconds
  SERVICE_RETRY_MOST = 10.minutes
  SERVICE_RETRY_ATTEMPTS = 150 # about a day at those gaps

  def self.service_retry_wait(executions)
    (SERVICE_RETRY_FIRST * 2**(executions - 1)).clamp(SERVICE_RETRY_FIRST, SERVICE_RETRY_MOST)
  end

  def self.waits_for_services(&gave_up)
    retry_on Remote::Unreachable, wait: ->(executions) { service_retry_wait(executions) }, attempts: SERVICE_RETRY_ATTEMPTS,
                                  jitter: 0, &gave_up
  end

  # How often a job checks back with ComfyUI for something it's making.
  COMFY_POLL = 3.seconds

  # One step of making something in ComfyUI (a ComfyRun record): submit it
  # when it isn't there yet (the block), collect what has landed, and, with
  # more to come, check back in a while (the job re-enqueues itself rather
  # than sleeping, so it never holds a worker while ComfyUI renders) until
  # it's all in, fails, or runs out of time. ComfyUI out of reach is waited
  # for (the record says so; waits_for_services retries); ComfyUI refusing
  # (a missing model, a bad graph) fails the record with its reason.
  def poll_comfy(record, client)
    return if record.finished?

    yield if record.unsubmitted?
    return if record.collect!(client)

    if record.timed_out?
      record.fail!("ComfyUI didn't finish within #{record.run_timeout.to_i / 60} minutes")
    else
      self.class.set(wait: COMFY_POLL).perform_later(record)
    end
  rescue Remote::Unreachable => e
    record.wait!(e.message)
    raise
  rescue Comfy::Error => e
    record.fail!(e.message)
  end
end
