// app/javascript/controllers/accordion_state_controller.js
import { Controller } from "@hotwired/stimulus"

const openCollapseIds = new Set()

export default class extends Controller {
  connect() {
    this.rememberShown = this.rememberShown.bind(this)
    this.rememberHidden = this.rememberHidden.bind(this)
    this.restoreOpenPanels = this.restoreOpenPanels.bind(this)

    this.element.addEventListener("shown.bs.collapse", this.rememberShown)
    this.element.addEventListener("hidden.bs.collapse", this.rememberHidden)
    document.addEventListener("turbo:morph", this.restoreOpenPanels)
    document.addEventListener("turbo:render", this.restoreOpenPanels)

    this.restoreOpenPanels()
  }

  disconnect() {
    this.element.removeEventListener("shown.bs.collapse", this.rememberShown)
    this.element.removeEventListener("hidden.bs.collapse", this.rememberHidden)
    document.removeEventListener("turbo:morph", this.restoreOpenPanels)
    document.removeEventListener("turbo:render", this.restoreOpenPanels)
  }

  rememberShown(event) {
    if (this.ownsCollapse(event.target)) openCollapseIds.add(event.target.id)
  }

  rememberHidden(event) {
    if (this.ownsCollapse(event.target)) openCollapseIds.delete(event.target.id)
  }

  restoreOpenPanels() {
    for (const id of openCollapseIds) {
      const collapse = document.getElementById(id)
      if (!collapse || !this.element.contains(collapse)) continue

      collapse.classList.remove("collapsing")
      collapse.classList.add("collapse", "show")
      collapse.style.height = ""

      for (const trigger of this.element.querySelectorAll("[data-bs-toggle='collapse']")) {
        if (trigger.getAttribute("data-bs-target") === `#${id}`) {
          trigger.classList.remove("collapsed")
          trigger.setAttribute("aria-expanded", "true")
        }
      }

      window.bootstrap?.Collapse.getOrCreateInstance(collapse, { toggle: false })
    }
  }

  ownsCollapse(element) {
    return element.id && element.classList.contains("accordion-collapse") && this.element.contains(element)
  }
}