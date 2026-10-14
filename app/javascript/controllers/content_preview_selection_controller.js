import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    contentId: String,
    tableId: String
  }

  connect() {
    document.addEventListener("change", this.syncFromRow)
    document.addEventListener("content-table-selection:connected", this.refresh)
    this.refresh()
  }

  disconnect() {
    document.removeEventListener("change", this.syncFromRow)
    document.removeEventListener("content-table-selection:connected", this.refresh)
  }

  change() {
    const rowCheckbox = this.rowCheckbox
    if (!rowCheckbox) {
      this.refresh()
      return
    }

    rowCheckbox.checked = this.element.checked
    rowCheckbox.dispatchEvent(new Event("change", { bubbles: true }))
  }

  syncFromRow = (event) => {
    const rowCheckbox = this.rowCheckbox
    if (event.target !== rowCheckbox) return

    this.element.checked = rowCheckbox.checked
  }

  refresh = () => {
    const rowCheckbox = this.rowCheckbox
    this.element.disabled = !rowCheckbox
    this.element.checked = rowCheckbox?.checked || false
  }

  get rowCheckbox() {
    const table = document.getElementById(this.tableIdValue)
    if (!table) return null

    return [...table.querySelectorAll("[data-content-table-selection-target~='row']")]
      .find((checkbox) => checkbox.value === this.contentIdValue)
  }
}
