import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, frameId: String }

  connect() {
    if (!window.bootstrap) return

    this.initialTitle = this.element.getAttribute("title") || this.element.getAttribute("data-bs-original-title")
    this.initialLabel = this.element.getAttribute("aria-label")
    this.tooltip = window.bootstrap.Tooltip.getOrCreateInstance(this.element)
    if (!this.hasUrlValue) return

    this.loadOnShow = () => this.load()
    this.clearBeforeCache = () => {
      this.tooltip.hide()
      this.resetFrame()
      this.tooltip.setContent({ ".tooltip-inner": this.initialTitle })
      if (this.initialLabel === null) {
        this.element.removeAttribute("aria-label")
      } else {
        this.element.setAttribute("aria-label", this.initialLabel)
      }
    }
    this.element.addEventListener("show.bs.tooltip", this.loadOnShow)
    document.addEventListener("turbo:before-cache", this.clearBeforeCache)
  }

  load() {
    if (this.frame) return

    const frame = document.createElement("turbo-frame")
    frame.id = this.frameIdValue
    frame.hidden = true
    frame.src = this.urlValue
    frame.addEventListener("turbo:frame-load", () => {
      if (this.frame !== frame || !this.element.isConnected) return

      const content = frame.textContent.trim()
      this.element.setAttribute("aria-label", content)
      this.tooltip.setContent({ ".tooltip-inner": content })
    })
    for (const eventName of ["turbo:frame-missing", "turbo:fetch-request-error"]) {
      frame.addEventListener(eventName, (event) => {
        event.preventDefault()
        if (this.frame === frame) this.resetFrame()
      })
    }
    this.frame = frame
    this.element.after(frame)
  }

  resetFrame() {
    this.frame?.remove()
    this.frame = null
  }

  disconnect() {
    if (this.loadOnShow) this.element.removeEventListener("show.bs.tooltip", this.loadOnShow)
    if (this.clearBeforeCache) document.removeEventListener("turbo:before-cache", this.clearBeforeCache)
    this.resetFrame()
    this.tooltip?.dispose()
  }
}
