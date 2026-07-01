import TurboNavigationController from "controllers/turbo_navigation_controller"

export default class extends TurboNavigationController {
  filter(event) {
    const id = Number(this.element.dataset.metadataFilterIdParam)
    const filter = event.target.value
    const metadataTypeReviewFilters = this.metadataTypeReviewFilters()

    delete metadataTypeReviewFilters[id]
    if (filter.length && filter !== "all") {
      metadataTypeReviewFilters[id] = filter === "UR"
    }

    const url = new URL(window.location.href)
    Array.from(url.searchParams.keys())
      .filter((key) => key === "f" || key.startsWith("f["))
      .forEach((key) => url.searchParams.delete(key))

    Object.entries(metadataTypeReviewFilters).forEach(([metadataTypeId, reviewFilter]) => {
      url.searchParams.append(`f[${metadataTypeId}]`, reviewFilter)
    })

    this.reload_page(url)
  }

  metadataTypeReviewFilters() {
    const url = new URL(window.location.href)
    const filters = {}

    Array.from(url.searchParams.entries()).forEach(([key, value]) => {
      if (key === "f") {
        filters["0"] = value
      } else if (key.startsWith("f[")) {
        const metadataTypeId = key.slice(2, -1)
        filters[metadataTypeId] = value
      }
    })

    return filters
  }

}
