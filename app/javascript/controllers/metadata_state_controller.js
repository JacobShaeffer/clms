import { Controller } from "@hotwired/stimulus"

export default class extends Controller {

    static values = {
        openAccordions: Array,
        metadataTypeSearches: Object,
        metadataTypeReviewFilters: Object,
        metadataTypeMetadataCounts: Object,
        metadataTypeModal: Number,
        metadatumModal: Number
    };

    static targets = [
        "query",
    ];

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

    

    reload_page(url){
        if (window.Turbo) {
            window.Turbo.visit(url.toString(), { action: "replace" });
        } else {
            window.location.assign(url.toString());
        }
    }

    on_accordion_toggle(event) {
        const id = Number(event.params["id"]);
        const openAccordions = [...this.openAccordionsValue];
        const idIndex = openAccordions.indexOf(id);

        if (idIndex === -1) {
            openAccordions.push(id);
        } else {
            openAccordions.splice(idIndex, 1);
        }

        this.openAccordionsValue = openAccordions;

        const url = new URL(window.location.href);
        url.searchParams.delete("oa[]");

        if (openAccordions.length) {
            openAccordions.forEach((id) => url.searchParams.append("oa[]", id));
        }

        this.reload_page(url);
    }

    search(event){
        const id = Number(event.params["id"]);
        const query = event.target.value;
        const metadataTypeSearches = { ...this.metadataTypeSearchesValue };

        if (query.length) {
            metadataTypeSearches[id] = query;
        } else {
            delete metadataTypeSearches[id];
        }

        this.metadataTypeSearchesValue = metadataTypeSearches;

        const url = new URL(window.location.href);
        Array.from(url.searchParams.keys())
            .filter((key) => key === "s" || key.startsWith("s["))
            .forEach((key) => url.searchParams.delete(key));

        Object.entries(metadataTypeSearches).forEach(([metadataTypeId, query]) => {
            if (query.length) {
                url.searchParams.append(`s[${metadataTypeId}]`, query);
            }
        });

        this.reload_page(url);
    }

    filter(event){
        const id = Number(event.params["id"]);
        const filter = event.target.value;
        const metadataTypeReviewFilters = { ...this.metadataTypeReviewFiltersValue};

        delete metadataTypeReviewFilters[id]
        if (filter.length && filter != "all") {
            metadataTypeReviewFilters[id] = filter == "UR" ? true : false;
            console.log(metadataTypeReviewFilters)
        }

        this.metadataTypeReviewFiltersValue = metadataTypeReviewFilters

        const url = new URL(window.location.href);
        Array.from(url.searchParams.keys())
            .filter((key) => key === "f" || key.startsWith("f["))
            .forEach((key) => url.searchParams.delete(key));

        Object.entries(metadataTypeReviewFilters).forEach(([metadataTypeId, filter]) => {
            console.log("filter: ", filter);
            url.searchParams.append(`f[${metadataTypeId}]`, filter);
        });

        this.reload_page(url);
    }
}
