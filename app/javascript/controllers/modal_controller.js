import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { preserve: Boolean }

  connect() {
    if (!window.bootstrap) {
      return
    }

    this.modal = new window.bootstrap.Modal(this.element)
    this.shown = false
    this.closing = false
    this.focusTitleAfterShown = false
    this.element.addEventListener("shown.bs.modal", this.markShown)
    this.element.addEventListener("hide.bs.modal", this.markClosing)
    if (this.preserveValue) {
      document.addEventListener("turbo:before-frame-render", this.beforeFrameRender)
      document.addEventListener("turbo:before-stream-render", this.beforeStreamRender)
    }
    this.modal.show()
    this.element.addEventListener("hidden.bs.modal", this.clearFrame, { once: true })
  }

  disconnect() {
    this.element.removeEventListener("shown.bs.modal", this.markShown)
    this.element.removeEventListener("hide.bs.modal", this.markClosing)
    this.element.removeEventListener("hidden.bs.modal", this.clearFrame)
    this.element.removeEventListener("shown.bs.modal", this.hideAfterShown)
    document.removeEventListener("turbo:before-frame-render", this.beforeFrameRender)
    document.removeEventListener("turbo:before-stream-render", this.beforeStreamRender)

    if (this.modal) {
      this.modal.dispose()
    }

    document.querySelectorAll(".modal-backdrop").forEach((backdrop) => backdrop.remove())
    document.body.classList.remove("modal-open")
    document.body.style.removeProperty("overflow")
    document.body.style.removeProperty("padding-right")
  }

  hide() {
    if (!this.modal) return

    if (this.shown) {
      this.modal.hide()
    } else {
      this.element.addEventListener("shown.bs.modal", this.hideAfterShown, { once: true })
    }
  }

  markShown = () => {
    this.shown = true
    if (this.focusTitleAfterShown) this.focusTitle()
  }

  markClosing = () => {
    this.closing = true
  }

  beforeFrameRender = (event) => {
    if (event.target !== this.element.closest("turbo-frame")) return

    const render = event.detail.render
    event.detail.render = (currentFrame, newFrame) => {
      if (!this.replaceContent(newFrame)) return render(currentFrame, newFrame)
    }
  }

  beforeStreamRender = (event) => {
    const stream = event.target
    if (stream.getAttribute("target") !== "modal" ||
        !["replace", "update"].includes(stream.getAttribute("action"))) return

    const render = event.detail.render
    event.detail.render = (currentStream) => {
      const content = currentStream.querySelector("template")?.content
      if (!this.replaceContent(content)) return render(currentStream)
    }
  }

  replaceContent(content) {
    const incomingModal = content?.querySelector('.modal[data-modal-preserve-value="true"]')
    if (!this.element.isConnected || this.closing || !this.modal || !incomingModal) return false

    const dialog = this.element.querySelector(".modal-dialog")
    const incomingDialog = incomingModal.querySelector(".modal-dialog")
    if (!dialog || !incomingDialog) return false

    // Bootstrap retains a reference to the dialog for transitions and backdrop clicks.
    dialog.className = incomingDialog.className
    // The transition focuses the title instead of the form's initial autofocus field.
    incomingDialog.querySelectorAll("[autofocus]").forEach((field) => field.removeAttribute("autofocus"))
    dialog.replaceChildren(...incomingDialog.childNodes)
    this.element.setAttribute("aria-labelledby", incomingModal.getAttribute("aria-labelledby"))
    this.modal.handleUpdate()
    this.focusTitleAfterShown = !this.shown
    if (this.shown) this.focusTitle()
    return true
  }

  focusTitle() {
    const title = this.element.querySelector(".modal-title")
    title?.setAttribute("tabindex", "-1")
    title?.focus({ preventScroll: true })
    this.focusTitleAfterShown = false
  }

  hideAfterShown = () => {
    this.shown = true
    this.modal?.hide()
  }

  clearFrame = () => {
    const frame = this.element.closest("turbo-frame")

    if (frame) {
      frame.innerHTML = ""
    }
  }
}
