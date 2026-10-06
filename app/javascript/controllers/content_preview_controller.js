import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
	static targets = ["container"]

	connect() {
		this.savedPreview = Array.from(this.containerTarget.childNodes, (node) => node.cloneNode(true))
		this.previewUrl = null
	}

	disconnect() {
		this.revokePreviewUrl()
	}

	show({ detail: { file } }) {
		this.revokePreviewUrl()
		this.previewUrl = URL.createObjectURL(file)
		this.containerTarget.replaceChildren(this.previewElement(file, this.previewUrl))
	}

	reset() {
		this.revokePreviewUrl()
		this.containerTarget.replaceChildren(
			...this.savedPreview.map((node) => node.cloneNode(true))
		)
	}

	previewElement(file, url) {
		switch (this.previewType(file)) {
			case "application/pdf":
				return this.pdfPreview(file, url)
			case "audio/mpeg":
				return this.audioPreview(url)
			case "video/mp4":
				return this.videoPreview(url)
			default:
				return this.unsupportedPreview()
		}
	}

	previewType(file) {
		if (["application/pdf", "audio/mpeg", "video/mp4"].includes(file.type)) return file.type

		const extension = file.name.split(".").pop()?.toLowerCase()
		return {
			pdf: "application/pdf",
			mp3: "audio/mpeg",
			mp4: "video/mp4"
		}[extension]
	}

	pdfPreview(file, url) {
		const preview = document.createElement("iframe")
		preview.src = url
		preview.className = "content-preview-pdf border rounded"
		preview.title = `PDF preview of ${file.name}`
		return preview
	}

	audioPreview(url) {
		const wrapper = document.createElement("div")
		wrapper.className = "d-flex justify-content-center py-5"

		const preview = document.createElement("audio")
		preview.className = "content-preview-audio w-100"
		preview.controls = true
		preview.preload = "metadata"
		preview.append(this.source(url, "audio/mpeg"), "Your browser does not support MP3 audio playback.")
		wrapper.append(preview)

		return wrapper
	}

	videoPreview(url) {
		const preview = document.createElement("video")
		preview.className = "content-preview-video w-100 bg-black rounded"
		preview.controls = true
		preview.preload = "metadata"
		preview.append(this.source(url, "video/mp4"), "Your browser does not support MP4 video playback.")
		return preview
	}

	source(url, type) {
		const source = document.createElement("source")
		source.src = url
		source.type = type
		return source
	}

	unsupportedPreview() {
		const warning = document.createElement("p")
		warning.className = "alert alert-warning mb-0"
		warning.role = "alert"
		warning.textContent = "This file type cannot be previewed."
		return warning
	}

	revokePreviewUrl() {
		if (!this.previewUrl) return

		URL.revokeObjectURL(this.previewUrl)
		this.previewUrl = null
	}
}
