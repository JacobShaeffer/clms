import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["actions", "item"]

  connect() {
    this.clear()
  }

  clear() {
    this.itemTargets.forEach((checkbox) => {
      checkbox.checked = false
    })

    this.update()
  }

  update() {
    if (!this.hasActionsTarget) return

    const hasSelection = this.itemTargets.some((checkbox) => checkbox.checked)

    this.actionsTarget.hidden = !hasSelection
    this.actionsTarget.classList.toggle("d-none", !hasSelection)
  }
}
