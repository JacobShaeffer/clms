import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.scrollY = null
    this.frame = null
  }

  captureScroll(event) {
    const link = event.target.closest("a[href]")
    const frame = link?.closest("turbo-frame")
    if (!frame) return

    this.scrollY = window.scrollY
    this.frame = frame
  }

  preserveScroll(event) {
    if (this.scrollY === null || event.target !== this.frame) return

    const scrollY = this.scrollY
    const render = event.detail.render
    this.scrollY = null
    this.frame = null

    event.detail.render = (currentFrame, newFrame) => {
      const result = render(currentFrame, newFrame)
      window.scrollTo({ top: scrollY, behavior: "instant" })
      return result
    }
  }
}
