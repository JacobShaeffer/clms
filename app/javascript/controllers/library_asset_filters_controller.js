import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["form", "query", "language", "assetType", "button", "newLink"]

  connect() {
    this.sync()
  }

  disconnect() {
    window.clearTimeout(this.timer)
  }

  search() {
    this.sync()
    window.clearTimeout(this.timer)
    this.timer = window.setTimeout(() => this.submit(), 200)
  }

  choose(event) {
    event.preventDefault()
    const button = event.currentTarget
    const field = button.name === "language" ? this.languageTarget : this.assetTypeTarget
    field.value = button.value
    this.sync()
    this.submit()
  }

  submit() {
    window.clearTimeout(this.timer)
    this.formTarget.requestSubmit()
  }

  sync() {
    const filters = { q: this.queryTarget.value, language: this.languageTarget.value, asset_type: this.assetTypeTarget.value }
    this.buttonTargets.forEach((button) => {
      const pressed = button.value === filters[button.name]
      button.classList.toggle("active", pressed)
      button.setAttribute("aria-pressed", String(pressed))
    })
    const url = new URL(this.newLinkTarget.href)
    Object.entries(filters).forEach(([field, value]) => {
      const key = `library_asset_filters[${field}]`
      if (value) url.searchParams.set(key, value)
      else url.searchParams.delete(key)
    })
    this.newLinkTarget.href = url.toString()
  }
}
