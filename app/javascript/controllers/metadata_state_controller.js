import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
    static values = {
        openAccordions: Array,
        metadataTypeSearches: Object,
        metadataTypeReviewFilters: Object,
        metadataTypeMetadataCounts: Object,
        metadataTypeModal: Number,
        metadatumModal: Number
    }

    connect() {
        console.log(
            this.openAccordionsValue, 
            this.metadataTypeSearchesValue, 
            this.metadataTypeReviewFiltersValue,
            this.metadataTypeMetadataCountsValue,
            this.metadataTypeModalValue,
            this.metadatumModalValue
        );
    }

    reload_page(openAccordions = this.openAccordionsValue) {
        const url = new URL(window.location.href);
        url.searchParams.delete("oa");
        url.searchParams.delete("oa[]");

        if (openAccordions.length) {
            openAccordions.forEach((id) => url.searchParams.append("oa[]", id));
        } else {
            url.searchParams.set("oa", "");
        }

        if (window.Turbo) {
            window.Turbo.visit(url.toString(), { action: "replace" });
        } else {
            window.location.assign(url.toString());
        }
    }

    accordion(event) {
        const id = Number(event.params["id"]);
        const openAccordions = [...this.openAccordionsValue];
        const idIndex = openAccordions.indexOf(id);

        if (idIndex === -1) {
            openAccordions.push(id);
        } else {
            openAccordions.splice(idIndex, 1);
        }

        this.openAccordionsValue = openAccordions;
        this.reload_page(openAccordions);
    }
}
