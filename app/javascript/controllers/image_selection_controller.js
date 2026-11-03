import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["selection", "preview", "name", "option", "results", "choose"]

  connect() {
    this.sync()
  }

  resultsTargetConnected() {
    if (this.hasSelectionTarget) this.sync()
  }

  select(event) {
    const option = event.currentTarget
    this.selectionTarget.value = option.dataset.assetId
    this.nameTarget.textContent = option.dataset.assetName
    this.previewTarget.replaceChildren(option.querySelector("[data-image-preview]").cloneNode(true))
    this.sync()
  }

  sync() {
    const selectedId = this.selectionTarget.value
    this.optionTargets.forEach((option) => {
      const selected = option.dataset.assetId === selectedId
      option.classList.toggle("active", selected)
      option.setAttribute("aria-pressed", String(selected))
    })
    this.chooseTarget.disabled = !selectedId
  }
}
