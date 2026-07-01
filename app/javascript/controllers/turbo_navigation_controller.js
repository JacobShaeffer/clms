import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  reload_page(url) {
    if (window.Turbo) {
      window.Turbo.visit(url.toString(), { action: "replace" })
    } else {
      window.location.assign(url.toString())
    }
  }
}