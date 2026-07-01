import TurboNavigationController from "controllers/turbo_navigation_controller"

export default class extends TurboNavigationController {
  connect() {
    this.debounceTimer = null
  }

  disconnect() {
    if (this.debounceTimer) {
      window.clearTimeout(this.debounceTimer)
    }
  }

  search(event) {
    const id = Number(this.element.dataset.metadataSearchIdParam)
    const query = event.target.value

    if (this.debounceTimer) {
      window.clearTimeout(this.debounceTimer)
    }

    this.debounceTimer = window.setTimeout(() => {
      const metadataTypeSearches = this.metadataTypeSearches()

      if (query.length) {
        metadataTypeSearches[id] = query
      } else {
        delete metadataTypeSearches[id]
      }

      const url = new URL(window.location.href)
      Array.from(url.searchParams.keys())
        .filter((key) => key === "s" || key.startsWith("s["))
        .forEach((key) => url.searchParams.delete(key))

      Object.entries(metadataTypeSearches).forEach(([metadataTypeId, searchQuery]) => {
        if (searchQuery.length) {
          url.searchParams.append(`s[${metadataTypeId}]`, searchQuery)
        }
      })

      this.reload_page(url)
    }, 150)
  }

  metadataTypeSearches() {
    const url = new URL(window.location.href)
    const searches = {}

    Array.from(url.searchParams.entries()).forEach(([key, value]) => {
      if (key === "s") {
        searches["0"] = value
      } else if (key.startsWith("s[")) {
        const metadataTypeId = key.slice(2, -1)
        searches[metadataTypeId] = value
      }
    })

    return searches
  }

}
