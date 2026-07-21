import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

export default class extends Controller {
	static targets = ["searchInput", "checkbox", "list"]
	static values = { type: Number, count: Number }

	async onAddSelected(event) {
		event.preventDefault()
		event.stopPropagation()

		const name = this.searchInputTarget.value.trim()
		if (!name) return

		const params = new URLSearchParams({
			target: this.badgeContainerId,
			metadata_type_id: this.typeValue,
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

		const metadatumId = event.currentTarget.dataset.metadatumId
		const checkbox = document.getElementById(`content_metadatum_ids_${metadatumId}`)

		if (checkbox) {
			checkbox.checked = !checkbox.checked
			document.getElementById(`metadatum_badge_${metadatumId}`).classList.toggle("d-none")
			event.currentTarget.classList.toggle("active", checkbox.checked)
		} else {
			const params = new URLSearchParams({
				target: this.badgeContainerId,
				metadata_type_id: this.typeValue,
				metadatum_id: metadatumId
			})

			await this.renderTurboStream(`/contents/add_existing_metadatum?${params}`)
		}

		this.searchInputTarget.value = ""
		this.autoComplete("")
	}

	onBadgeClicked(event) {
		event.preventDefault()
		event.stopPropagation()

		const metadatumId = event.currentTarget.dataset.metadatumId
		const checkbox = document.getElementById(`content_metadatum_ids_${metadatumId}`)
		if (!checkbox) return

		checkbox.checked = false
		event.currentTarget.classList.add("d-none")

		const listItem = document.getElementById(`selector_for=${metadatumId}`)
		listItem?.classList.remove("active")
	}

	onSearchFocusIn() {
		this.listTarget.classList.remove("d-none")
		this.autoComplete(this.searchInputTarget.value)
	}

	onSearchFocusOut() {
		this.listTarget.classList.add("d-none")
	}

	onSearchInput(event) {
		this.autoComplete(event.currentTarget.value)
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

	autoComplete(search) {
		const selectedIds = this.checkboxTargets
			.filter((checkbox) => checkbox.checked)
			.map((checkbox) => checkbox.value)
			.join(",")

		const params = new URLSearchParams({
			target: this.listTarget.id,
			metadata_type_id: this.typeValue,
			search,
			selected_ids: selectedIds,
			metadatum_count: this.countValue
		})

		this.renderTurboStream(`/contents/search?${params}`)
	}

	get badgeContainerId() {
		return `metadataBadge_${this.typeValue}_container`
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
	}
}
