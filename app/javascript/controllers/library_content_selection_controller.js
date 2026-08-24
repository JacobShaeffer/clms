import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["scope"]

  initialize() {
    this.selectionsByScope = new Map()
  }

  scopeTargetConnected(scope) {
    this.restoreSelection(scope)
  }

  update(event) {
    const scope = event.target.closest("[data-library-content-selection-target~='scope']")
    if (!scope) return

    this.storeRenderedSelection(scope)
  }

  frameRendered(event) {
    const scope = this.currentScope
    if (!scope) return

    if (scope.contains(event.target)) {
      this.storeRenderedSelection(scope)
    }
  }

  tableConnected(event) {
    const scope = event.target.closest("[data-library-content-selection-target~='scope']")
    if (!scope) return

    this.restoreSelection(scope)
  }

  clearAfterSubmit(event) {
    if (!event.detail.success) return

    const scope = this.currentScope
    if (!scope) return

    this.selectedIds(scope).clear()
    this.restoreSelection(scope)
  }

  prepareSubmit() {
    const scope = this.currentScope
    if (!scope) return

    this.restoreSelection(scope)
  }

  restoreSelection(scope) {
    const selectedIds = this.selectedIds(scope)

    this.rowCheckboxes(scope).forEach((checkbox) => {
      checkbox.checked = selectedIds.has(checkbox.value)
    })

    this.updatePageCheckbox(scope)
  }

  storeRenderedSelection(scope) {
    this.selectionsByScope.set(
      this.scopeName(scope),
      new Set(
        this.rowCheckboxes(scope)
          .filter((checkbox) => checkbox.checked)
          .map((checkbox) => checkbox.value)
      )
    )
  }

  updatePageCheckbox(scope) {
    const pageCheckbox = scope.querySelector(this.pageSelector)
    if (!pageCheckbox) return

    const rows = this.rowCheckboxes(scope)
    const selectedRows = rows.filter((checkbox) => checkbox.checked).length
    pageCheckbox.checked = rows.length > 0 && selectedRows === rows.length
    pageCheckbox.indeterminate = selectedRows > 0 && selectedRows < rows.length
  }

  selectedIds(scope) {
    const scopeName = this.scopeName(scope)

    if (!this.selectionsByScope.has(scopeName)) {
      this.selectionsByScope.set(scopeName, new Set())
    }

    return this.selectionsByScope.get(scopeName)
  }

  scopeName(scope) {
    return scope.dataset.libraryContentSelectionScope
  }

  rowCheckboxes(scope) {
    return [...scope.querySelectorAll(this.rowSelector)]
  }

  get currentScope() {
    return this.scopeTargets[0]
  }

  get rowSelector() {
    return "[data-content-table-selection-target~='row']"
  }

  get pageSelector() {
    return "[data-content-table-selection-target~='page']"
  }
}
