import { Controller } from "@hotwired/stimulus"

// A form whose fields depend on a choice (a kind's medium): anything marked
// data-show-for="image audio" shows only while the select is one of those.
// A hidden <fieldset> is disabled too, so its fields don't submit: two
// sections can each have a field of the same name (a kind's model). The page
// starts in the same state (rendered so), for a browser without JS.
export default class extends Controller {
  static targets = ["select"]

  connect() {
    this.update()
  }

  update() {
    const value = this.selectTarget.value
    this.element.querySelectorAll("[data-show-for]").forEach((el) => {
      const shown = el.dataset.showFor.split(" ").includes(value)
      el.hidden = !shown
      if (el instanceof HTMLFieldSetElement) el.disabled = !shown
    })
  }
}
