import { Controller } from "@hotwired/stimulus"

// A notice ("Saved.", "Cid has a new pick") floats over the page for a
// moment, wherever you'd scrolled to. Tap it to send it away sooner.
const NOTICE_MS = 6000
const ALERT_MS = 10000

export default class extends Controller {
  connect() {
    const ms = this.element.getAttribute("role") === "alert" ? ALERT_MS : NOTICE_MS
    this.timer = setTimeout(() => this.dismiss(), ms)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    const box = this.element.parentElement
    this.element.remove()
    if (box && !box.children.length) box.remove()
  }
}
