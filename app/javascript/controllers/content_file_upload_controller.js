import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
	static targets = ["input", "blob", "status", "submit"]
	static values = { url: String }

	connect() {
		this.requestNumber = 0
		this.abortController = null
	}

	disconnect() {
		this.abortController?.abort()
	}

	async upload() {
		const requestNumber = ++this.requestNumber
		this.abortController?.abort()
		this.removeBlob()
		this.resetFieldState()

		const file = this.inputTarget.files[0]
		if (!file) {
			this.showError("File can't be blank")
			return
		}

		this.abortController = new AbortController()
		this.setSubmitting(false)
		this.showStatus(`Uploading and checking ${file.name}…`)

		const body = new FormData()
		body.append("file", file)

		try {
			const response = await fetch(this.urlValue, {
				method: "POST",
				body,
				headers: {
					Accept: "application/json",
					"X-CSRF-Token": this.csrfToken
				},
				signal: this.abortController.signal
			})
			const result = await response.json()

			if (requestNumber !== this.requestNumber) return

			if (response.ok) {
				this.addBlob(result.signed_id)
				this.inputTarget.classList.add("is-valid")
				this.showStatus(`Uploaded and validated: ${result.filename}`, "text-success")
				this.setSubmitting(true)
			} else {
				this.showError(result.errors || ["File could not be validated"])
			}
		} catch (error) {
			if (error.name !== "AbortError" && requestNumber === this.requestNumber) {
				this.showError("File upload failed. Select the file again to retry.")
			}
		}
	}

	prepareSubmission() {
		if (this.hasBlobTarget) this.inputTarget.disabled = true
	}

	addBlob(signedId) {
		const input = document.createElement("input")
		input.type = "hidden"
		input.name = "content[file]"
		input.value = signedId
		input.dataset.contentFileUploadTarget = "blob"
		this.inputTarget.insertAdjacentElement("afterend", input)
	}

	removeBlob() {
		if (this.hasBlobTarget) this.blobTarget.remove()
	}

	resetFieldState() {
		this.inputTarget.classList.remove("is-valid", "is-invalid")
		this.statusTarget.classList.remove("text-success", "text-danger")
		this.statusTarget.textContent = ""
	}

	showError(messages) {
		this.inputTarget.classList.add("is-invalid")
		this.showErrors(Array.isArray(messages) ? messages : [messages])
		this.setSubmitting(false)
	}

	showErrors(messages) {
		const lines = messages.flatMap((message, index) => {
			const text = document.createTextNode(message)
			return index === 0 ? [text] : [document.createElement("br"), text]
		})

		this.statusTarget.replaceChildren(...lines)
		this.statusTarget.classList.add("text-danger")
	}

	showStatus(message, className = null) {
		this.statusTarget.textContent = message
		if (className) this.statusTarget.classList.add(className)
	}

	setSubmitting(enabled) {
		this.submitTargets.forEach((submit) => { submit.disabled = !enabled })
	}

	get csrfToken() {
		return document.querySelector("meta[name='csrf-token']")?.content
	}
}
