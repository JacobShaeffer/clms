import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "label", "option"]

  select(event) {
    this.inputTarget.value = event.currentTarget.dataset.value
    this.update()
  }

  clear() {
    this.inputTarget.value = ""
    this.update()
  }

  update() {
    this.optionTargets.forEach((option) => {
      const selected = option.dataset.value === this.inputTarget.value
      option.classList.toggle("active", selected)
      option.setAttribute("aria-selected", String(selected))
      if (selected) this.labelTarget.replaceChildren(...Array.from(option.childNodes, (node) => node.cloneNode(true)))
    })
  }
}
