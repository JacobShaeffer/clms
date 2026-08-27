import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "item", "empty"]

  filter() {
    const query = this.inputTarget.value.trim().toLocaleLowerCase()
    let visibleCount = 0

    this.itemTargets.forEach((item) => {
      const name = item.dataset.metadataValueName.toLocaleLowerCase()
      const matches = name.includes(query)

      item.classList.toggle("d-none", !matches)
      if (matches) visibleCount += 1
    })

    this.emptyTarget.classList.toggle("d-none", visibleCount > 0)
  }
}
