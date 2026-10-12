import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["shelf", "submit"]

  connect() {
    this.update()
  }

  update() {
    const selectedShelves = this.shelfTargets.filter((checkbox) => checkbox.checked).length

    this.submitTarget.value = selectedShelves === 0
      ? "Add to NEW Shelf"
      : selectedShelves === 1 ? "Add to Shelf" : "Add to Shelves"
  }
}
