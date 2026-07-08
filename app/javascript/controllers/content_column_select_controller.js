import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["qField", "perPageField"]

  submit() {
    this.syncCurrentFilters()
    this.syncColumnSelectionFields()
    this.element.requestSubmit()
  }

  syncCurrentFilters() {
    const qSource = document.querySelector("[data-content-column-select-source='q']")
    const perPageSource = document.querySelector("[data-content-column-select-source='per-page']")

    if (this.hasQFieldTarget) {
      this.qFieldTarget.value = qSource ? qSource.value : this.qFieldTarget.value
    }

    if (this.hasPerPageFieldTarget) {
      this.perPageFieldTarget.value = perPageSource ? perPageSource.value : this.perPageFieldTarget.value
    }
  }

  syncColumnSelectionFields() {
    const selectedColumnKeys = Array
      .from(this.element.querySelectorAll("input[name='columns[]']:checked"))
      .map((input) => input.value)

    document.querySelectorAll("[data-column-selection-sync='true']").forEach((form) => {
      form.querySelectorAll("[data-column-selection-field='true']").forEach((field) => field.remove())
      form.appendChild(this.hiddenField("columns_present", "1"))
      selectedColumnKeys.forEach((columnKey) => form.appendChild(this.hiddenField("columns[]", columnKey)))
    })
  }

  hiddenField(name, value) {
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    input.dataset.columnSelectionField = "true"

    return input
  }
}
