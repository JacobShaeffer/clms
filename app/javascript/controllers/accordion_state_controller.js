import TurboNavigationController from "controllers/turbo_navigation_controller"

export default class extends TurboNavigationController {
  toggle() {
    const id = Number(this.element.dataset.accordionStateIdParam)
    const openAccordions = this.openAccordions()
    const idIndex = openAccordions.indexOf(id)

    if (idIndex === -1) {
      openAccordions.push(id)
    } else {
      openAccordions.splice(idIndex, 1)
    }

    const url = new URL(window.location.href)
    url.searchParams.delete("oa[]")

    if (openAccordions.length) {
      openAccordions.forEach((openId) => url.searchParams.append("oa[]", openId))
    }

    this.reload_page(url)
  }

  openAccordions() {
    const url = new URL(window.location.href)
    return Array.from(url.searchParams.getAll("oa[]"))
      .map((value) => Number(value))
      .filter((value) => Number.isFinite(value))
  }
}
