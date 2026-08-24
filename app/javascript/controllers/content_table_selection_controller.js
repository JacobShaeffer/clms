import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["page", "row"]
  static values = { preserveBeforeCache: Boolean }

  connect() {
    this.selectionSnapshots = new WeakMap()
    this.responseSelectionSnapshots = new WeakMap()
    this.resetRows()
    this.update()
    this.dispatch("connected")
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

  captureSelection(event) {
    this.selectionSnapshots.set(event.detail.formSubmission, {
      selectedRowIds: new Set(
        this.rowTargets.filter((checkbox) => checkbox.checked).map((checkbox) => checkbox.value)
      ),
      visibleRowIds: new Set(this.rowTargets.map((checkbox) => checkbox.value))
    })
  }

  trackSelectionResponse(event) {
    const { fetchResponse, formSubmission, success } = event.detail
    const snapshot = this.selectionSnapshots.get(formSubmission)

    this.selectionSnapshots.delete(formSubmission)

    if (snapshot && success && fetchResponse) {
      this.responseSelectionSnapshots.set(fetchResponse, snapshot)
    }
  }

  restoreSelection(event) {
    const { fetchResponse } = event.detail
    const snapshot = this.responseSelectionSnapshots.get(fetchResponse)

    if (!snapshot) return

    this.responseSelectionSnapshots.delete(fetchResponse)

    const visibleRowIds = new Set(this.rowTargets.map((checkbox) => checkbox.value))
    const rowsUnchanged = this.setsEqual(snapshot.visibleRowIds, visibleRowIds)

    this.rowTargets.forEach((checkbox) => {
      checkbox.checked = rowsUnchanged && snapshot.selectedRowIds.has(checkbox.value)
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
    if (this.preserveBeforeCacheValue) return

    this.resetRows()
  }

  resetRows() {
    this.rowTargets.forEach((checkbox) => {
      checkbox.checked = false
    })

    if (this.hasPageTarget) {
      this.pageTarget.checked = false
      this.pageTarget.indeterminate = false
    }

    this.update()
  }

  setsEqual(first, second) {
    return first.size === second.size && [...first].every((value) => second.has(value))
  }
}
