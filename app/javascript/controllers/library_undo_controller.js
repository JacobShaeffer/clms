import { Controller } from "@hotwired/stimulus"

// Memory belongs to this visit, not a Turbo snapshot or browser storage.
let pageSession = null

function sessionId() {
  if (crypto.randomUUID) return crypto.randomUUID()
  const bytes = crypto.getRandomValues(new Uint8Array(16))
  bytes[6] = (bytes[6] & 15) | 64
  bytes[8] = (bytes[8] & 63) | 128
  const hex = Array.from(bytes, (byte) => byte.toString(16).padStart(2, "0")).join("")
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`
}

function samePage(url, session = pageSession) {
  if (!session) return false
  const destination = new URL(url, window.location.href)
  const version = destination.searchParams.get("library_version_id")
  return destination.origin === window.location.origin && destination.pathname === session.path &&
    (!version || version === session.version)
}

document.addEventListener("turbo:before-visit", (event) => {
  if (!samePage(event.detail.url)) pageSession = null
})
document.addEventListener("turbo:before-render", (event) => {
  const incoming = event.detail.newBody.querySelector('[data-controller~="library-undo"]')
  if (!incoming || incoming.dataset.libraryUndoPagePathValue !== pageSession?.path ||
      incoming.dataset.libraryUndoVersionValue !== pageSession?.version) pageSession = null
})
window.addEventListener("pagehide", () => { pageSession = null })

export default class extends Controller {
  static targets = ["undo", "redo", "status"]
  static values = { pagePath: String, version: String, statusUrl: String, undoUrl: String, redoUrl: String }

  connect() {
    this.connectSession()
    document.addEventListener("submit", this.beforeSubmit, true)
    document.addEventListener("turbo:submit-start", this.editStarted)
    document.addEventListener("turbo:submit-end", this.editFinished)
    document.addEventListener("turbo:before-fetch-request", this.beforeRequest)
    document.addEventListener("turbo:before-fetch-response", this.editResponse)
    document.addEventListener("turbo:frame-load", this.refresh)
    document.addEventListener("turbo:load", this.refresh)
    document.addEventListener("turbo:before-cache", this.beforeCache)
    document.addEventListener("visibilitychange", this.visibilityChanged)
    window.addEventListener("focus", this.refresh)
    window.addEventListener("pageshow", this.restoredPage)
    this.draw()
    this.refresh()
  }

  connectSession() {
    if (!pageSession || pageSession.path !== this.pagePathValue || pageSession.version !== this.versionValue) {
      pageSession = {
        path: this.pagePathValue, version: this.versionValue, id: sessionId(),
        undo: [], redo: [], availability: new Map(), busy: false, message: ""
      }
    }
    this.session = pageSession
  }

  disconnect() {
    clearTimeout(this.refreshTimer)
    document.removeEventListener("submit", this.beforeSubmit, true)
    document.removeEventListener("turbo:submit-start", this.editStarted)
    document.removeEventListener("turbo:submit-end", this.editFinished)
    document.removeEventListener("turbo:before-fetch-request", this.beforeRequest)
    document.removeEventListener("turbo:before-fetch-response", this.editResponse)
    document.removeEventListener("turbo:frame-load", this.refresh)
    document.removeEventListener("turbo:load", this.refresh)
    document.removeEventListener("turbo:before-cache", this.beforeCache)
    document.removeEventListener("visibilitychange", this.visibilityChanged)
    window.removeEventListener("focus", this.refresh)
    window.removeEventListener("pageshow", this.restoredPage)
  }

  restoredPage = (event) => {
    if (!event.persisted) return
    pageSession = null
    this.connectSession()
    this.draw()
  }

  beforeRequest = (event) => {
    if (pageSession !== this.session) return
    if (this.libraryRequest(event.detail.url)) {
      event.detail.fetchOptions.headers["X-Library-Page-Session"] = this.session.id
    }
  }

  libraryRequest(url) {
    const destination = new URL(url, window.location.href)
    return destination.origin === window.location.origin && destination.pathname.startsWith(`${this.session.path}/`)
  }

  libraryEdit(form) {
    return form instanceof HTMLFormElement && form.method.toLowerCase() !== "get" && this.libraryRequest(form.action)
  }

  beforeSubmit = (event) => {
    if (pageSession !== this.session || !this.session.busy || !this.libraryEdit(event.target)) return
    event.preventDefault()
    event.stopImmediatePropagation()
    this.session.message = "Wait for the current library edit to finish."
    this.draw()
  }

  editStarted = (event) => {
    if (pageSession !== this.session || !this.libraryEdit(event.target)) return
    this.session.busy = true
    this.draw()
  }

  editFinished = (event) => {
    if (pageSession !== this.session || !this.libraryEdit(event.detail.formSubmission.formElement)) return
    this.session.busy = false
    this.draw()
    this.refresh()
  }

  editResponse = (event) => {
    if (pageSession !== this.session) return
    const response = event.detail.fetchResponse.response
    const receipt = response.headers.get("X-Library-Edit-Receipt")
    if (!response.ok || !receipt || response.headers.get("X-Library-Page-Session") !== this.session.id) return
    this.session.undo.push(receipt)
    this.session.undo = this.session.undo.slice(-3)
    this.session.redo = []
    this.session.availability.clear()
    this.session.message = ""
    this.draw()
    this.refresh()
  }

  visibilityChanged = () => {
    if (!document.hidden) this.refresh()
  }

  beforeCache = () => {
    this.undoTarget.disabled = true
    this.redoTarget.disabled = true
    this.statusTarget.textContent = ""
    this.undoTarget.removeAttribute("title")
    this.redoTarget.removeAttribute("title")
  }

  refresh = () => {
    clearTimeout(this.refreshTimer)
    this.refreshTimer = setTimeout(() => this.checkAvailability(), 50)
  }

  async checkAvailability() {
    if (pageSession !== this.session || !this.element.isConnected || this.session.busy) return
    await Promise.all(["undo", "redo"].map(async (direction) => {
      const receipt = this.session[direction].at(-1)
      if (!receipt) return
      const url = new URL(this.statusUrlValue, window.location.href)
      url.searchParams.set("receipt", receipt)
      url.searchParams.set("direction", direction)
      let result
      try {
        const response = await fetch(url, { headers: this.headers(), cache: "no-store" })
        result = await response.json()
      } catch {
        result = { available: false, reason: "Unable to check this edit. Try again when the connection is restored." }
      }
      if (pageSession === this.session && !this.session.busy && this.session[direction].at(-1) === receipt) {
        this.session.availability.set(receipt, result)
      }
    }))
    if (pageSession === this.session && this.element.isConnected) this.draw()
  }

  undo() { return this.apply("undo") }
  redo() { return this.apply("redo") }

  async apply(direction) {
    const receipt = this.session[direction].at(-1)
    if (!receipt || this.session.busy || pageSession !== this.session) return
    this.session.busy = true
    this.draw()
    try {
      const current = new URL(window.location.href)
      const activeTab = document.querySelector('[aria-labelledby="library-content-heading"] .nav-link.active')
      const panel = activeTab ? new URL(activeTab.href, current) : current
      const folder = document.querySelector('[data-library-folder-actions-target="folderState"]')
      const response = await fetch(direction === "undo" ? this.undoUrlValue : this.redoUrlValue, {
        method: "PATCH", headers: { ...this.headers(), "Content-Type": "application/json" },
        body: JSON.stringify({ receipt, context: {
          folder_id: folder?.dataset.folderId || null,
          tab: panel.searchParams.get("tab") || "all", shelf_id: panel.searchParams.get("shelf_id")
        } })
      })
      const result = await response.json()
      if (pageSession !== this.session) return
      if (!response.ok) {
        const reason = result.reason || "This edit is no longer available."
        this.session.availability.set(receipt, { available: false, reason })
      } else {
        this.session[direction].pop()
        this.session[direction === "undo" ? "redo" : "undo"].push(result.receipt)
        this.session.availability.clear()
        this.session.message = result.message
        window.Turbo.visit(result.url, { action: "replace" })
      }
    } catch {
      this.session.message = "The request could not be completed. Check your connection and try again."
    } finally {
      this.session.busy = false
      if (pageSession === this.session && this.element.isConnected) {
        this.draw()
        this.refresh()
      }
    }
  }

  headers() {
    return {
      Accept: "application/json", "X-Library-Page-Session": this.session.id,
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content || ""
    }
  }

  draw() {
    const reasons = []
    for (const direction of ["undo", "redo"]) {
      const receipt = this.session[direction].at(-1)
      const availability = this.session.availability.get(receipt)
      const button = direction === "undo" ? this.undoTarget : this.redoTarget
      button.disabled = this.session.busy || !receipt || !availability?.available
      button.title = availability?.label ? `${direction === "undo" ? "Undo" : "Redo"}: ${availability.label}` : ""
      if (receipt && availability?.reason) reasons.push(`${direction === "undo" ? "Undo" : "Redo"}: ${availability.reason}`)
    }
    this.statusTarget.textContent = reasons.join(" ") || this.session.message
  }
}
