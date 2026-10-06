// Custom Turbo Stream actions.
//
// reload_frame: reload one Turbo Frame in place. A batch sends it as each
// candidate lands (Batch#refresh_watchers), so only the studio's batches
// update and the rest of the page, a half-typed form included, is left alone.
const { StreamActions } = window.Turbo

StreamActions.reload_frame = function () {
  const frame = document.getElementById(this.target)
  if (!frame) return
  if (frame.src) frame.reload()
  else frame.src = frame.dataset.src
}
