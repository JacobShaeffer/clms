import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    if (!window.bootstrap) {
      return
    }

    this.modal = new window.bootstrap.Modal(this.element)
    this.modal.show()
    this.element.addEventListener("hidden.bs.modal", this.clearFrame, { once: true })
  }

  disconnect() {
    if (this.modal) {
      this.modal.dispose()
    }

    document.querySelectorAll(".modal-backdrop").forEach((backdrop) => backdrop.remove())
    document.body.classList.remove("modal-open")
    document.body.style.removeProperty("overflow")
    document.body.style.removeProperty("padding-right")
  }

  clearFrame = () => {
    const frame = this.element.closest("turbo-frame")

    if (frame) {
      frame.innerHTML = ""
    }
  }
}
