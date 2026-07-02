import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["frame"]
  static values = { url: String }

  load() {
    if (!this.hasFrameTarget || !this.hasUrlValue || this.frameTarget.src) {
      return
    }

    this.frameTarget.src = this.urlValue
  }
}
