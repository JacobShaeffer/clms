import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
  static values = { url: String }

  navigate(event) {
    if (event.type === "click" && event.target.closest("a, button, input, select, textarea")) {
      return
    }

    event.preventDefault()
    Turbo.visit(this.urlValue)
  }
}
