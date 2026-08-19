import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["folderState", "folderInput"]

  folderStateTargetConnected() {
    this.sync()
  }

  folderStateTargetDisconnected() {
    this.sync()
  }

  folderInputTargetConnected(target) {
    target.value = this.folderId
  }

  sync() {
    this.folderInputTargets.forEach((target) => {
      target.value = this.folderId
    })
  }

  get folderId() {
    return this.hasFolderStateTarget ? this.folderStateTarget.dataset.folderId || "" : ""
  }
}
