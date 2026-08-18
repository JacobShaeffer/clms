import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["page", "row"]

  connect() {
    this.clearRows()
    this.update()
  }

  rowTargetConnected() {
    this.update()
  }

  rowTargetDisconnected() {
    this.update()
  }

  togglePage(event) {
    this.rowTargets.forEach((checkbox) => {
      checkbox.checked = event.currentTarget.checked
    })
    this.update()
  }

  update() {
    const selectedRows = this.rowTargets.filter((checkbox) => checkbox.checked).length

    if (this.hasPageTarget) {
      this.pageTarget.checked = this.rowTargets.length > 0 && selectedRows === this.rowTargets.length
      this.pageTarget.indeterminate = selectedRows > 0 && selectedRows < this.rowTargets.length
    }
  }

  clearRows() {
    this.rowTargets.forEach((checkbox) => {
      checkbox.checked = false
    })

    if (this.hasPageTarget) {
      this.pageTarget.checked = false
      this.pageTarget.indeterminate = false
    }

    this.update()
  }
}
