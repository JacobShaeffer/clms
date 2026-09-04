class LibraryFolderSelectionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library
  before_action :authorize_management
  before_action :ensure_current_version

  rescue_from LibraryFolderOperations::Selection::InvalidSelection, with: :render_invalid_selection
  rescue_from ActiveRecord::RecordInvalid, ActiveRecord::RecordNotDestroyed, with: :render_invalid_selection

  def remove_confirmation
    @selection = build_selection

    render partial: "library_folder_selections/remove_confirmation_modal"
  end

  def remove
    LibraryFolderOperations::Remove.call(library: @library, **selection_attributes)

    render_success("Selected items were removed.")
  end

  def move
    render_destination(:move)
  end

  def apply_move
    LibraryFolderOperations::Move.call(
      library: @library,
      **selection_attributes,
      destination_folder_id: params[:destination_folder_id]
    )

    render_success("Selected items were moved.")
  end

  def duplicate
    render_destination(:duplicate)
  end

  def apply_duplicate
    LibraryFolderOperations::Duplicate.call(
      library: @library,
      **selection_attributes,
      destination_folder_id: params[:destination_folder_id],
      user: current_user
    )

    render_success("Selected items were duplicated.")
  end

  private

  def set_library
    @library = policy_scope(Library).find(params.expect(:library_id))
  end

  def authorize_management
    authorize LibraryFolder, :manage?
  end

  def ensure_current_version
    return if params[:library_version_id].blank?

    requested_version = @library.library_versions.find(scalar_id!(:library_version_id))
    return if requested_version.id == @library.current_version_id

    raise LibraryFolderOperations::Selection::InvalidSelection,
      "Only the current library version can be changed."
  end

  def build_selection
    LibraryFolderOperations::Selection.new(library: @library, **selection_attributes)
  end

  def selection_attributes
    {
      source_folder_id: params[:source_folder_id],
      folder_ids: params[:folder_ids],
      content_ids: params[:content_ids]
    }
  end

  def render_destination(operation)
    @selection = build_selection
    @picker = LibraryFolderOperations::DestinationPicker.new(
      library: @library,
      selection: @selection,
      operation:,
      current_folder_id: params[:picker_folder_id]
    )
    @operation = operation

    render partial: "library_folder_selections/destination_modal"
  end

  def render_success(message)
    respond_to do |format|
      format.turbo_stream do
        flash[:notice] = message
        render turbo_stream: turbo_stream.refresh(request_id: nil)
      end
      format.html do
        redirect_to library_path(@library, page_context_params), notice: message, status: :see_other
      end
    end
  end

  def render_invalid_selection(error)
    @error_message = error.message

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "modal",
          partial: "library_folder_selections/selection_error_modal"
        ), status: :unprocessable_content
      end
      format.html do
        if turbo_frame_request?
          render partial: "library_folder_selections/selection_error_modal", status: :unprocessable_content
        else
          redirect_to library_path(@library, page_context_params),
            alert: @error_message,
            status: :see_other
        end
      end
    end
  end

  def page_context_params
    {
      folder_id: optional_scalar(params[:source_folder_id], "source folder"),
      tab: normalized_tab,
      shelf_id: optional_scalar(params[:shelf_id], "shelf"),
      library_version_id: optional_scalar(params[:library_version_id], "library version")
    }.compact
  end

  def scalar_id!(key)
    value = params[key]
    return value if value.is_a?(String) || value.is_a?(Integer)

    raise ActiveRecord::RecordNotFound, "Invalid #{key}"
  end

  def normalized_tab
    tab = params[:tab]
    tab.is_a?(String) && LibrariesController::CONTENT_TABS.include?(tab) ? tab : "all"
  end

  def optional_scalar(value, label)
    return if value.blank?
    return value if value.is_a?(String) || value.is_a?(Integer)

    raise LibraryFolderOperations::Selection::InvalidSelection, "Invalid #{label}."
  end
end
