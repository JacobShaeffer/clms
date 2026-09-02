class LibraryFoldersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library
  before_action :set_page_context
  before_action :set_parent_folder
  before_action :set_picker_context
  before_action :load_library_assets, only: %i[ new create ]

  rescue_from LibraryFolderOperations::Selection::InvalidSelection, with: :render_picker_context_error

  def new
    @library_folder = @library.library_folders.build(
      parent_folder: @parent_folder,
      user: current_user
    )
    authorize @library_folder

    render partial: "library_folders/modal_form" if turbo_frame_request?
  end

  def create
    @library_folder = @library.library_folders.build(
      name: library_folder_params[:name],
      parent_folder: @parent_folder,
      user: current_user
    )
    authorize @library_folder
    assign_root_logo

    respond_to do |format|
      if @library_folder.save
        format.turbo_stream { render_folder_creation_success }
        format.html do
          redirect_to library_path(@library, page_context_params),
            notice: "Folder was successfully created.",
            status: :see_other
        end
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "modal",
            partial: "library_folders/modal_form"
          ), status: :unprocessable_content
        end
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  private

  def set_library
    @library = policy_scope(Library).find(params.expect(:library_id))
  end

  def set_page_context
    requested_tab = params[:tab]
    @active_tab = requested_tab.is_a?(String) && LibrariesController::CONTENT_TABS.include?(requested_tab) ? requested_tab : "all"
    return unless @active_tab == "shelves" && params[:shelf_id].present?

    requested_shelf_id = Integer(scalar_id!(:shelf_id), exception: false)
    active_shelf = current_user.active_shelves.includes(:shelf).find_by(shelf_id: requested_shelf_id)
    raise ActiveRecord::RecordNotFound, "Active shelf not found" unless active_shelf

    @selected_shelf = active_shelf.shelf
  end

  def set_parent_folder
    return if params[:parent_folder_id].blank?

    @parent_folder = @library.library_folders.find(scalar_id!(:parent_folder_id))
  end

  def set_picker_context
    return if params[:picker_operation].blank?

    @picker_operation = params[:picker_operation].to_s.to_sym
    unless LibraryFolderOperations::DestinationPicker::OPERATIONS.include?(@picker_operation)
      raise LibraryFolderOperations::Selection::InvalidSelection, "Invalid folder operation."
    end

    @selection = LibraryFolderOperations::Selection.new(
      library: @library,
      source_folder_id: params[:source_folder_id],
      folder_ids: params[:folder_ids],
      content_ids: params[:content_ids]
    )
    LibraryFolderOperations::DestinationPicker.new(
      library: @library,
      selection: @selection,
      operation: @picker_operation,
      current_folder_id: @parent_folder&.id
    )
  end

  def load_library_assets
    @library_assets = @parent_folder ? LibraryAsset.none : policy_scope(LibraryAsset).order(:name, :id)
  end

  def assign_root_logo
    return if @parent_folder

    logo_id = library_folder_params[:logo_id]
    @library_folder.logo = policy_scope(LibraryAsset).find(scalar_value!(logo_id)) if logo_id.present?
  end

  def load_folder_browser(current_folder: @parent_folder)
    folders = @library.library_folders.order(:name, :id).to_a
    @folder_path_index = LibraryFolderPathIndex.new(library: @library, folders:)
    @current_folder = current_folder
    @breadcrumb_folders = @current_folder ? @folder_path_index.path(@current_folder) : []
    @browser_folders = if @current_folder
      folders.select { |folder| folder.parent_folder_id == @current_folder.id }
    else
      folders.select { |folder| folder.parent_folder_id.nil? }
    end
    @browser_contents = @current_folder ? @current_folder.contents.order(Content.arel_table[:title].lower, :id).to_a : []
  end

  def library_folder_params
    params.expect(library_folder: [ :name, :logo_id ])
  end

  def page_context_params
    {
      folder_id: @parent_folder&.id,
      tab: @active_tab,
      shelf_id: @selected_shelf&.id
    }.compact
  end

  def scalar_id!(key)
    scalar_value!(params[key], key:)
  end

  def scalar_value!(value, key: :id)
    return value if value.is_a?(String) || value.is_a?(Integer)

    raise ActiveRecord::RecordNotFound, "Invalid #{key}"
  end

  def render_folder_creation_success
    unless @picker_operation
      load_folder_browser
      render turbo_stream: [
        turbo_stream.update("modal", ""),
        turbo_stream.replace(
          helpers.dom_id(@library, :folder_browser),
          partial: "libraries/folder_browser"
        )
      ]
      return
    end

    @selection = LibraryFolderOperations::Selection.new(
      library: @library,
      source_folder_id: params[:source_folder_id],
      folder_ids: params[:folder_ids],
      content_ids: params[:content_ids]
    )
    load_folder_browser(current_folder: @selection.source_folder)
    @picker = LibraryFolderOperations::DestinationPicker.new(
      library: @library,
      selection: @selection,
      operation: @picker_operation,
      current_folder_id: @library_folder.id
    )
    @operation = @picker_operation

    render turbo_stream: [
      turbo_stream.replace(
        helpers.dom_id(@library, :folder_browser),
        partial: "libraries/folder_browser"
      ),
      turbo_stream.replace(
        "modal",
        partial: "library_folder_selections/destination_modal"
      )
    ]
  end

  def render_picker_context_error(error)
    @error_message = error.message

    if turbo_frame_request?
      render partial: "library_folder_selections/selection_error_modal", status: :unprocessable_content
    else
      redirect_to library_path(@library), alert: @error_message, status: :see_other
    end
  end
end
