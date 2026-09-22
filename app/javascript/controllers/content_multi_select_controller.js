import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

const LIST_HIDE_DELAY = 150

export default class extends Controller {
	static targets = ["searchInput", "checkbox", "list", "dropdown", "badgeContainer", "badge", "selector"]
	static values = {
		type: Number,
		count: Number,
		componentId: String,
		selectionContext: String,
		allowCreate: Boolean
	}

	connect() {
		this.hideListTimer = null
		this.showListFrame = null
		this.searchAbortController = null
		this.boundOnListTransitionEnd = this.onListTransitionEnd.bind(this)
		this.dropdownTarget.addEventListener("transitionend", this.boundOnListTransitionEnd)
	}

	disconnect() {
		this.cancelListVisibilityChanges()
		this.dropdownTarget.removeEventListener("transitionend", this.boundOnListTransitionEnd)
		this.searchAbortController?.abort()
	}

	async onAddSelected(event) {
		event.preventDefault()
		event.stopPropagation()

		const name = this.searchInputTarget.value.trim()
		if (!name) return

		const params = new URLSearchParams({
			target: this.badgeContainerTarget.id,
			metadata_type_id: this.typeValue,
			component_id: this.componentIdValue,
			selection_context: this.selectionContextValue,
			name
		})

		await this.renderTurboStream("/contents/add_new_metadatum", {
			method: "POST",
			body: params,
			headers: { "X-CSRF-Token": this.csrfToken }
		})

		this.searchInputTarget.value = ""
		this.autoComplete("")
	}

	async onItemSelected(event) {
		event.preventDefault()
		event.stopPropagation()

		const selector = event.currentTarget
		const metadatumId = selector.dataset.metadatumId
		const checkbox = this.checkboxFor(metadatumId)

		if (checkbox) {
			checkbox.checked = !checkbox.checked
			this.badgeFor(metadatumId)?.classList.toggle("d-none", !checkbox.checked)
			selector.classList.toggle("active", checkbox.checked)
		} else {
			const params = new URLSearchParams({
				target: this.badgeContainerTarget.id,
				metadata_type_id: this.typeValue,
				component_id: this.componentIdValue,
				selection_context: this.selectionContextValue,
				metadatum_id: metadatumId
			})

			await this.renderTurboStream(`/contents/add_existing_metadatum?${params}`)
			selector.classList.add("active")
		}

		this.searchInputTarget.value = ""
		this.autoComplete("")
	}

	onBadgeClicked(event) {
		event.preventDefault()
		event.stopPropagation()

		const metadatumId = event.currentTarget.dataset.metadatumId
		const checkbox = this.checkboxFor(metadatumId)
		if (!checkbox) return

		checkbox.checked = false
		event.currentTarget.classList.add("d-none")

		const listItem = this.selectorFor(metadatumId)
		listItem?.classList.remove("active")
	}

	clear() {
		this.hideListImmediately()
		this.searchAbortController?.abort()
		this.searchAbortController = null
		this.checkboxTargets.forEach((checkbox) => { checkbox.checked = false })
		this.badgeTargets.forEach((badge) => badge.classList.add("d-none"))
		this.searchInputTarget.value = ""
		this.listTarget.replaceChildren()
	}

	async onSearchFocusIn() {
		if (this.listTarget.childElementCount > 0) this.showList()

		const rendered = await this.autoComplete(this.searchInputTarget.value)
		if (rendered && this.searchInputTarget.matches(":focus") && !this.dropdownTarget.classList.contains("is-open")) {
			this.showList()
		}
	}

	onSearchFocusOut() {
		this.cancelHideListTimer()
		this.hideListTimer = window.setTimeout(() => {
			this.hideListTimer = null
			this.dropdownTarget.classList.remove("is-open")

			if (this.prefersReducedMotion) this.dropdownTarget.classList.add("d-none")
		}, LIST_HIDE_DELAY)
	}

	async onSearchInput(event) {
		const rendered = await this.autoComplete(event.currentTarget.value)
		if (rendered && this.searchInputTarget.matches(":focus") && !this.dropdownTarget.classList.contains("is-open")) {
			this.showList()
		}
	}

	onSearchInputClick() {
		this.searchInputTarget.focus()
	}

	onShowMore(event) {
		event.preventDefault()
		event.stopPropagation()

		this.countValue += 5
		this.autoComplete(this.searchInputTarget.value)
	}

	showList() {
		this.cancelListVisibilityChanges()
		this.dropdownTarget.classList.remove("d-none")

		if (this.prefersReducedMotion) {
			this.dropdownTarget.classList.add("is-open")
			return
		}

		this.showListFrame = window.requestAnimationFrame(() => {
			this.showListFrame = null
			this.dropdownTarget.classList.add("is-open")
		})
	}

	onListTransitionEnd(event) {
		if (event.target !== this.dropdownTarget || event.propertyName !== "opacity") return
		if (this.dropdownTarget.classList.contains("is-open")) return

		this.dropdownTarget.classList.add("d-none")
	}

	hideListImmediately() {
		this.cancelListVisibilityChanges()
		this.dropdownTarget.classList.remove("is-open")
		this.dropdownTarget.classList.add("d-none")
	}

	cancelListVisibilityChanges() {
		this.cancelHideListTimer()

		if (this.showListFrame) {
			window.cancelAnimationFrame(this.showListFrame)
			this.showListFrame = null
		}
	}

	cancelHideListTimer() {
		if (!this.hideListTimer) return

		window.clearTimeout(this.hideListTimer)
		this.hideListTimer = null
	}

	get prefersReducedMotion() {
		return window.matchMedia?.("(prefers-reduced-motion: reduce)").matches
	}

	async autoComplete(search) {
		const selectedIds = this.checkboxElements
			.filter((checkbox) => checkbox.checked)
			.map((checkbox) => checkbox.value)
			.join(",")

		const params = new URLSearchParams({
			target: this.listTarget.id,
			metadata_type_id: this.typeValue,
			component_id: this.componentIdValue,
			selection_context: this.selectionContextValue,
			allow_create: this.allowCreateValue ? "1" : "0",
			search,
			selected_ids: selectedIds,
			metadatum_count: this.countValue
		})

		this.searchAbortController?.abort()
		const abortController = new AbortController()
		this.searchAbortController = abortController

		try {
			await this.renderTurboStream(`/contents/search?${params}`, { signal: abortController.signal })
		} catch (error) {
			if (error.name === "AbortError") return false
			throw error
		} finally {
			if (this.searchAbortController === abortController) this.searchAbortController = null
		}

		return true
	}

	checkboxFor(metadatumId) {
		return this.checkboxElements.find((checkbox) => checkbox.value === metadatumId)
	}

	badgeFor(metadatumId) {
		return this.badgeTargets.find((badge) => badge.dataset.metadatumId === metadatumId)
	}

	selectorFor(metadatumId) {
		return this.selectorTargets.find((selector) => selector.dataset.metadatumId === metadatumId)
	}

	get checkboxElements() {
		return Array.from(
			this.element.querySelectorAll('[data-content-multi-select-target~="checkbox"]')
		)
	}

	get csrfToken() {
		return document.querySelector("meta[name='csrf-token']")?.content
	}

	async renderTurboStream(url, options = {}) {
		const response = await fetch(url, {
			...options,
			headers: {
				Accept: "text/vnd.turbo-stream.html",
				...options.headers
			}
		})

		const body = await response.text()
		if (!response.ok) throw new Error(`Metadata request failed (${response.status})`)

		Turbo.renderStreamMessage(body)
		await new Promise((resolve) => window.requestAnimationFrame(resolve))
	}
}
