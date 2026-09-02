class LibrariesController < ApplicationController
  CONTENT_TABS = %w[all shelves library].freeze
  ADD_TO_ACTIVE_FOLDER_STATUS_ID = "library-add-to-active-folder-status"

  before_action :authenticate_user!
  before_action :set_library, only: %i[
    show
    all_contents_table reset_all_contents_table
    library_contents_table reset_library_contents_table
    shelf_contents_table reset_shelf_contents_table
    add_to_active_folder
  ]

  def index
    authorize Library

    @libraries = ordered_libraries
  end

  def show
    authorize @library

    @active_tab = normalized_tab
    load_folder_browser
    load_content_panel
  end

  def all_contents_table
    authorize @library
    load_all_contents_table

    render partial: "content_tables/table_frame", locals: table_locals
  end

  def reset_all_contents_table
    authorize @library
    delete_table_preference(ContentTables::LibraryContentsDefinition.all_content_state_key(@library))

    redirect_to library_path(@library, tab: "all"), status: :see_other
  end

  def library_contents_table
    authorize @library
    load_library_contents_table

    render partial: "content_tables/table_frame", locals: table_locals
  end

  def reset_library_contents_table
    authorize @library
    delete_table_preference(ContentTables::LibraryContentsDefinition.library_content_state_key(@library))

    redirect_to library_path(@library, tab: "library"), status: :see_other
  end

  def shelf_contents_table
    authorize @library
    load_active_shelves
    load_selected_active_shelf!
    load_shelf_contents_table

    render partial: "content_tables/table_frame", locals: table_locals
  end

  def reset_shelf_contents_table
    authorize @library
    load_active_shelves
    load_selected_active_shelf!
    delete_table_preference(
      ContentTables::LibraryContentsDefinition.shelf_content_state_key(@library, @selected_shelf)
    )

    redirect_to library_path(
      @library,
      tab: "shelves",
      shelf_id: @selected_shelf.id
    ), status: :see_other
  end

  def add_to_active_folder
    authorize @library

    return render_add_to_active_folder_error("Open a folder before adding content.") if params[:folder_id].blank?

    @current_folder = @library_version.library_folders.find(scalar_id!(:folder_id))
    content_ids = selected_ids(:content_ids)
    return render_add_to_active_folder_error("Select at least one content item.") if content_ids.empty?

    permitted_content_ids = policy_scope(Content).where(id: content_ids).pluck(:id)
    unless permitted_content_ids.sort == content_ids.sort
      return render_add_to_active_folder_error("One or more selected content items is unavailable.")
    end

    validate_placement_context! if request.format.turbo_stream?
    placement_result = LibraryFolderOperations::PlaceContents.call(
      library: @library,
      folder_id: @current_folder.id,
      content_ids:
    )
    message = add_to_active_folder_message(placement_result)

    respond_to do |format|
      format.turbo_stream do
        load_folder_browser
        load_content_panel

        render turbo_stream: [
          turbo_stream.replace(
            helpers.dom_id(@library, :folder_browser),
            partial: "libraries/folder_browser"
          ),
          turbo_stream.replace(
            @table_definition.frame_id,
            partial: "content_tables/table_frame",
            locals: table_locals
          ),
          turbo_stream.update(
            ADD_TO_ACTIVE_FOLDER_STATUS_ID,
            partial: "libraries/add_to_active_folder_status",
            locals: { message:, type: :success }
          )
        ]
      end
      format.html do
        redirect_to library_path(@library, placement_context_params),
          notice: message,
          status: :see_other
      end
    end
  rescue LibraryFolderOperations::Selection::InvalidSelection => error
    render_add_to_active_folder_error(error.message)
  end

  def new
    @library = current_user.libraries.build
    authorize @library

    render partial: "libraries/modal_form", locals: { library: @library } if turbo_frame_request?
  end

  def create
    @library = current_user.libraries.build(library_params)
    authorize @library

    respond_to do |format|
      if @library.save
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update("modal", ""),
            turbo_stream.update(
              "libraries",
              partial: "libraries/table_rows",
              locals: { libraries: ordered_libraries }
            )
          ]
        end
        format.html { redirect_to @library, notice: "Library was successfully created." }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "modal",
            partial: "libraries/modal_form",
            locals: { library: @library }
          ), status: :unprocessable_content
        end
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  private

  def normalized_tab
    requested_tab = params[:tab]
    requested_tab.is_a?(String) && CONTENT_TABS.include?(requested_tab) ? requested_tab : "all"
  end

  def load_content_panel
    if @active_tab == "shelves" || params[:shelf_id].present?
      load_active_shelves
      load_selected_active_shelf! if params[:shelf_id].present?
    end

    case @active_tab
    when "all"
      load_all_contents_table
    when "library"
      load_library_contents_table
    when "shelves"
      load_shelf_contents_table if @selected_shelf
    end
  end

  def load_folder_browser
    folders = @library_version.library_folders.order(:name, :id).to_a
    @folder_path_index = LibraryFolderPathIndex.new(
      library: @library,
      library_version: @library_version,
      folders:
    )
    @current_folder = @library_version.library_folders.find(scalar_id!(:folder_id)) if params[:folder_id].present?
    @breadcrumb_folders = @current_folder ? @folder_path_index.path(@current_folder) : []
    @browser_folders = if @current_folder
      folders.select { |folder| folder.parent_folder_id == @current_folder.id }
    else
      folders.select { |folder| folder.parent_folder_id.nil? }
    end
    @browser_contents = if @current_folder
      @current_folder.contents.with_attached_file.order(Content.arel_table[:title].lower, :id).to_a
    else
      []
    end
    @file_changed_content_ids = @library_version
      .file_changed_content_ids(@browser_contents)
      .index_with(true)
  end

  def load_active_shelves
    @active_shelf_records = current_user.active_shelves.includes(:shelf).ordered.to_a
  end

  def load_selected_active_shelf!
    requested_shelf_id = Integer(scalar_id!(:shelf_id), exception: false)
    active_shelf = @active_shelf_records.find { |record| record.shelf_id == requested_shelf_id }
    raise ActiveRecord::RecordNotFound, "Active shelf not found" unless active_shelf

    @selected_shelf = active_shelf.shelf
  end

  def load_all_contents_table
    load_contents_table(
      source: base_content_source,
      state_key: ContentTables::LibraryContentsDefinition.all_content_state_key(@library),
      frame_id: "library_#{@library.id}_all_contents_table",
      update_path: all_contents_table_library_path(@library),
      reset_path: reset_all_contents_table_library_path(@library)
    )
  end

  def load_library_contents_table
    content_ids = @library_version.library_folder_contents.select(:content_id)
    load_contents_table(
      source: base_content_source.where(id: content_ids),
      state_key: ContentTables::LibraryContentsDefinition.library_content_state_key(@library),
      frame_id: "library_#{@library.id}_library_contents_table",
      update_path: library_contents_table_library_path(@library),
      reset_path: reset_library_contents_table_library_path(@library)
    )
  end

  def load_shelf_contents_table
    load_contents_table(
      source: base_content_source.where(id: @selected_shelf.contents.select(:id)),
      state_key: ContentTables::LibraryContentsDefinition.shelf_content_state_key(@library, @selected_shelf),
      frame_id: "library_#{@library.id}_shelf_#{@selected_shelf.id}_contents_table",
      update_path: shelf_contents_table_library_path(@library, shelf_id: @selected_shelf.id),
      reset_path: reset_shelf_contents_table_library_path(@library, shelf_id: @selected_shelf.id),
      search_enabled: false,
      filters_enabled: false
    )
  end

  def load_contents_table(
    source:,
    state_key:,
    frame_id:,
    update_path:,
    reset_path:,
    search_enabled: true,
    filters_enabled: true
  )
    @table_definition = ContentTables::LibraryContentsDefinition.new(
      library: @library,
      library_version: @library_version,
      source:,
      metadata_types: policy_scope(MetadataType).order(:order, :name),
      update_path:,
      reset_path:,
      state_key:,
      frame_id:,
      search_enabled:,
      filters_enabled:,
      path_index: @folder_path_index,
      selection_form_id: "#{frame_id}_add_to_active_folder_form"
    )
    table = ContentTables::Coordinator.call(
      user: current_user,
      definition: @table_definition,
      params:,
      paginator: method(:paginate_contents)
    )
    @table_state = table.state
    @pagy = table.pagy
    @contents = table.records
  end

  def base_content_source
    policy_scope(Content).includes(
      :user,
      metadata: :metadata_type
    )
  end

  def paginate_contents(relation:, page:, per_page:)
    pagy(:offset, relation, limit: per_page, page:)
  end

  def delete_table_preference(table_key)
    current_user.content_table_preferences.find_by(table_key:)&.destroy!
  end

  def table_locals
    {
      definition: @table_definition,
      state: @table_state,
      records: @contents,
      pagy: @pagy
    }
  end

  def selected_ids(key)
    Array(params[key]).filter_map { |value| Integer(value, exception: false) }.uniq
  end

  def validate_placement_context!
    @active_tab = normalized_tab
    return unless @active_tab == "shelves"

    load_active_shelves
    load_selected_active_shelf!
  end

  def add_to_active_folder_message(result)
    if result.none_added?
      "The selected content is already in the active folder."
    elsif result.some_skipped?
      "Content was added to the active folder. Existing placements were skipped."
    else
      "Content was added to the active folder."
    end
  end

  def render_add_to_active_folder_error(message)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.update(
          ADD_TO_ACTIVE_FOLDER_STATUS_ID,
          partial: "libraries/add_to_active_folder_status",
          locals: { message:, type: :error }
        ), status: :unprocessable_content
      end
      format.html do
        redirect_to library_path(@library, placement_context_params),
          alert: message,
          status: :see_other
      end
    end
  end

  def placement_context_params
    {
      folder_id: params[:folder_id].presence,
      tab: normalized_tab,
      shelf_id: params[:shelf_id].presence
    }.compact
  end

  def scalar_id!(key)
    value = params[key]
    return value if value.is_a?(String) || value.is_a?(Integer)

    raise ActiveRecord::RecordNotFound, "Invalid #{key}"
  end

  def set_library
    @library = policy_scope(Library).find(params.expect(:id))
    @library_version = @library.current_version
  end

  def ordered_libraries
    policy_scope(Library)
      .includes(:current_version)
      .order(:name, :id)
      .load
  end

  def library_params
    params.expect(library: [ :name ])
  end
end
