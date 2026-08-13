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

  clearFilters(event) {
    event.preventDefault()

    this.element.querySelectorAll("[name^='filters[']").forEach((control) => {
      if (control.matches("input[type='checkbox'], input[type='radio']")) {
        control.checked = false
      } else if (control.matches("select")) {
        control.selectedIndex = -1
      } else {
        control.value = ""
      }
    })

    this.element.requestSubmit(event.currentTarget)
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
