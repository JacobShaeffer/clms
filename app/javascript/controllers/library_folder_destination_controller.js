import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["destination", "submit"]

  connect() {
    this.update()
  }

  update() {
    this.submitTarget.disabled = !this.hasDestinationTarget ||
      this.destinationTarget.disabled ||
      !this.destinationTarget.value
  }
}
