import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["change"]

  select(event) {
    if (event.target.id !== "modal") return

    this.clear()
    const details = event.target.querySelector("[data-library-change-details]")
    if (!details) return

    const dependentIds = new Set(JSON.parse(details.dataset.dependentChangeIds).map(String))
    this.changeTargets.forEach((row) => {
      const selected = row.dataset.changeId === details.dataset.changeId
      row.classList.toggle("library-change-selected", selected)
      row.classList.toggle("library-change-dependent", dependentIds.has(row.dataset.changeId))
      if (selected) row.querySelector("a").setAttribute("aria-current", "true")
    })
  }

  clear() {
    this.changeTargets.forEach((row) => {
      row.classList.remove("library-change-selected", "library-change-dependent")
      row.querySelector("a").removeAttribute("aria-current")
    })
  }
}
