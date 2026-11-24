import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  connect() {
    const url = new URL(window.location.href)
    if (url.searchParams.get("timezone")) return
    try {
      const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone
      if (!timezone) return
      url.searchParams.set("timezone", timezone)
      window.location.replace(url.toString())
    } catch (_) {
      // The server renders the report in UTC when timezone detection is unavailable.
    }
  }
}
