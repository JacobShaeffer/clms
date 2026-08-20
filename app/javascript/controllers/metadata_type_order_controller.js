import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["item"]

  connect() {
    this.updateButtons()
  }

  moveUp(event) {
    const item = event.currentTarget.closest("[data-metadata-type-order-target='item']")
    const previousItem = item.previousElementSibling

    if (previousItem) {
      item.parentElement.insertBefore(item, previousItem)
      this.updateButtons()
    }
  }

  moveDown(event) {
    const item = event.currentTarget.closest("[data-metadata-type-order-target='item']")
    const nextItem = item.nextElementSibling

    if (nextItem) {
      item.parentElement.insertBefore(nextItem, item)
      this.updateButtons()
    }
  }

  updateButtons() {
    this.itemTargets.forEach((item, index) => {
      item.querySelector("[data-action='metadata-type-order#moveUp']").disabled = index === 0
      item.querySelector("[data-action='metadata-type-order#moveDown']").disabled = index === this.itemTargets.length - 1
    })
  }
}
