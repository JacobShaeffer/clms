import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    this.debounceTimer = null
  }

  disconnect() {
    if (this.debounceTimer) {
      window.clearTimeout(this.debounceTimer)
    }
  }

  submit(event) {
    if (event.type === "input") {
      this.debounceSubmit()
      return
    }

    this.submitForm()
  }

  debounceSubmit() {
    if (this.debounceTimer) {
      window.clearTimeout(this.debounceTimer)
    }

    this.debounceTimer = window.setTimeout(() => this.submitForm(), 150)
  }

  submitForm() {
    this.element.requestSubmit()
  }
}
