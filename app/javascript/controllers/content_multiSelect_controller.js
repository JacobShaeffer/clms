import { Controller } from "@hotwired/stimulus"
import { get } from "@rails/request.js"

export const string_identifier = "multiSelect";

export default class extends Controller {
	static targets = ["searchInput", "checkbox"]
	static values = {
		type: String,
		count: Number
	}

    // initialize() {
    // 	// Called once, when the controller is first instantiated
	// 	console.log("multiselect controller initialized")
	// }

	onAddSelected(event) {
		let name = this.searchInputTarget.value;
		this.searchInputTarget.value = "";
		this.autoComplete("");

		let params = new URLSearchParams();

		let target = `metadataBadge_${this.typeValue}_container`;

		params.append("target", target);
		params.append("metadata_type_id", this.typeValue);
		params.append("name", name);

		get(`/contents/add_new_metadatum?${params}`, {
			responseKind: "turbo-stream", 
		});
	}

	onItemSelected(event) {
		// console.log("onItemSelected", event.target.id);
		var metadatum_id = event.target.id.substr(13);
		var badge_id = "metadatum_badge_" + metadatum_id;

		var checkbox_id = "content_metadatum_ids_" + metadatum_id;
		var checkbox = document.getElementById(checkbox_id);
		if (!!checkbox){
			// this checkbox already exists 
			var isChecked = checkbox.checked;
			document.getElementById(checkbox_id).checked = !isChecked;

			document.getElementById(badge_id).classList.toggle("hidden");
			event.target.classList.toggle("active");
		}
		else{
			// checkbox does not exist
			let params = new URLSearchParams();
			let target = `metadataBadge_${this.typeValue}_container`;

			params.append("target", target);
			params.append("metadata_type_id", this.typeValue);
			params.append("metadatum_id", metadatum_id);
			console.log(target, this.typeValue, metadatum_id);

			get(`/contents/add_existing_metadatum?${params}`, {
				responseKind: "turbo-stream",
			});
		}


		this.searchInputTarget.value = "";
		this.autoComplete("");
	}

	onBadgeClicked(event) {
		// console.log("onBadgeClicked", event.target.id);
		var target_id = event.target.id.substr(21);
		// console.log("target_id", target_id);
		var listItem_id = "selector_for=" + target_id;

		var checkbox_id = "content_metadatum_ids_" + target_id;
		var isChecked = document.getElementById(checkbox_id).checked;
		document.getElementById(checkbox_id).checked = !isChecked;

		let selector_for = document.getElementById(listItem_id);
		if (selector_for) {
			selector_for.classList.toggle("active");
		}
		event.target.parentElement.classList.toggle("hidden");
	}

	onSearchFocusIn(event) {
		this.autoComplete(this.searchInputTarget.value);
		document.getElementById(event.target.id + "_list").classList.toggle("hidden");
	}

	onSearchFocusOut(event) {
		document.getElementById(event.target.id + "_list").classList.toggle("hidden");
	}

	onSearchInput(event) {
		// console.log("onSearchInput")
		this.autoComplete(event.target.value);
	}

	onSearchInputClick(){
		// console.log("onSearchInputClick")
		this.searchInputTarget.focus();
	}

	onShowMore(event){
		// preventDefault and stopPropagation to prevent focus from shifting to button
		event.preventDefault();
		event.stopPropagation();

		this.countValue += 5;
		this.autoComplete(this.searchInputTarget.value);
	}

	// Private

	autoComplete(search){
		let params = new URLSearchParams();

		let selected_ids = this.checkboxTargets.filter((checkbox) => 
			checkbox.checked).map((checkbox) => checkbox.value).join(",");

		let target = `metadataInput_${this.typeValue}_list`;

		params.append("target", target);
		params.append("metadata_type_id", this.typeValue);
		params.append("search", search);
		params.append("selected_ids", selected_ids);
		params.append("metadatum_count", this.countValue);

		get(`/contents/search?${params}`, {
			responseKind: "turbo-stream", 
		})
	}

	toggleCheckBox(target_id){
		var checkbox_id = "content_metadatum_ids_" + target_id;
		var isChecked = document.getElementById(checkbox_id).checked;
		document.getElementById(checkbox_id).checked = !isChecked;
	}
}