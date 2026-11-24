import { Controller } from "@hotwired/stimulus"

const DAY_IN_MS = 24 * 60 * 60 * 1000

export default class extends Controller {
  static targets = ["form", "week", "details", "heading", "days"]
  static values = { date: String, selected: String }

  connect() {
    this.focusDate = this.parseDate(this.dateValue)
    this.month = new Date(this.focusDate)
    this.month.setUTCDate(1)
    this.render()
  }

  previousMonth() {
    this.moveMonth(-1)
  }

  nextMonth() {
    this.moveMonth(1)
  }

  moveMonth(offset) {
    this.month.setUTCMonth(this.month.getUTCMonth() + offset)
    this.focusDate = new Date(this.month)
    this.render()
  }

  select(event) {
    const button = event.target.closest("button[data-date]")
    if (!button) return

    this.weekTarget.value = button.dataset.date
    this.formTarget.requestSubmit()
  }

  keydown(event) {
    const button = event.target.closest("button[data-date]")
    if (!button) return

    const offsets = { ArrowLeft: -1, ArrowRight: 1, ArrowUp: -7, ArrowDown: 7 }
    let offset = offsets[event.key]
    const date = this.parseDate(button.dataset.date)
    if (event.key === "Home") offset = -((date.getUTCDay() + 6) % 7)
    if (event.key === "End") offset = 6 - ((date.getUTCDay() + 6) % 7)
    if (event.key === "Escape") {
      event.preventDefault()
      this.detailsTarget.open = false
      this.detailsTarget.querySelector("summary").focus()
      return
    }
    if (offset === undefined) return

    event.preventDefault()
    this.focusDate = new Date(date.getTime() + offset * DAY_IN_MS)
    this.month = new Date(this.focusDate)
    this.month.setUTCDate(1)
    this.render()
    this.daysTarget.querySelector("button[tabindex='0']")?.focus()
  }

  render() {
    this.headingTarget.textContent = new Intl.DateTimeFormat("en", {
      month: "long", year: "numeric", timeZone: "UTC"
    }).format(this.month)
    const firstDay = new Date(this.month)
    firstDay.setUTCDate(1 - ((firstDay.getUTCDay() + 6) % 7))
    const selectedStart = this.selectedValue ? this.parseDate(this.selectedValue).getTime() : null
    const dateFormatter = new Intl.DateTimeFormat("en", {
      weekday: "long", year: "numeric", month: "long", day: "numeric", timeZone: "UTC"
    })
    const fragment = document.createDocumentFragment()

    for (let row = 0; row < 6; row++) {
      const tr = document.createElement("tr")
      for (let column = 0; column < 7; column++) {
        const date = new Date(firstDay.getTime() + (row * 7 + column) * DAY_IN_MS)
        const td = document.createElement("td")
        const button = document.createElement("button")
        const inSelectedWeek = selectedStart !== null && date.getTime() >= selectedStart && date.getTime() < selectedStart + 7 * DAY_IN_MS
        button.type = "button"
        button.className = `btn btn-sm ${inSelectedWeek ? "btn-primary" : "btn-light"}`
        if (date.getUTCMonth() !== this.month.getUTCMonth() && !inSelectedWeek) button.classList.add("text-body-secondary")
        button.dataset.date = this.isoDate(date)
        button.textContent = String(date.getUTCDate())
        button.setAttribute("aria-label", dateFormatter.format(date))
        button.setAttribute("aria-pressed", String(inSelectedWeek))
        button.tabIndex = this.isoDate(date) === this.isoDate(this.focusDate) ? 0 : -1
        td.append(button)
        tr.append(td)
      }
      fragment.append(tr)
    }
    this.daysTarget.replaceChildren(fragment)
  }

  parseDate(value) {
    const [year, month, day] = value.split("-").map(Number)
    const date = new Date(0)
    date.setUTCHours(0, 0, 0, 0)
    date.setUTCFullYear(year, month - 1, day)
    return date
  }

  isoDate(date) {
    const year = String(date.getUTCFullYear()).padStart(4, "0")
    const month = String(date.getUTCMonth() + 1).padStart(2, "0")
    const day = String(date.getUTCDate()).padStart(2, "0")
    return `${year}-${month}-${day}`
  }
}
