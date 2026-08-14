import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (!window.bootstrap) return

    this.tooltip = window.bootstrap.Tooltip.getOrCreateInstance(this.element)
  }

  disconnect() {
    this.tooltip?.dispose()
  }
}
