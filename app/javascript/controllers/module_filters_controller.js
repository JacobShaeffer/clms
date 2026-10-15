import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "query", "contextLink"]

  connect() {
    this.syncLinks()
  }

  disconnect() {
    window.clearTimeout(this.timer)
  }

  search() {
    this.syncLinks()
    window.clearTimeout(this.timer)
    this.timer = window.setTimeout(() => this.formTarget.requestSubmit(), 200)
  }

  syncLinks() {
    this.contextLinkTargets.forEach((link) => {
      const url = new URL(link.href)
      const key = "module_filters[q]"

      if (this.queryTarget.value) {
        url.searchParams.set(key, this.queryTarget.value)
      } else {
        url.searchParams.delete(key)
      }

      link.href = url.toString()
    })
  }
}
