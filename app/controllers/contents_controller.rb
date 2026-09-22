class ContentsController < ApplicationController
  MAX_METADATA_SEARCH_RESULTS = 100
  ADD_TO_SHELVES_FORM_ID = "contents-add-to-shelves-form"
  ADD_TO_SHELVES_STATUS_ID = "contents-add-to-shelves-status"

  before_action :authenticate_user!
  before_action :set_content, only: %i[show edit update]
  before_action :load_metadata_types, only: %i[new create edit update]

  def index
    authorize Content
    load_active_shelves
    load_contents_table
  end

  def table
    authorize Content
    load_contents_table

    render partial: "content_tables/table_frame", locals: table_locals
  end

  def reset_table
    authorize Content

    current_user.content_table_preferences.find_by(
      table_key: ContentTables::ContentsDefinition::STATE_KEY
    )&.destroy!
    session.delete("contents_index_state")

    redirect_to contents_path, status: :see_other
  end

  def add_to_shelves
    authorize Content

    content_ids = selected_ids(:content_ids)
    shelf_ids = selected_ids(:shelf_ids)
    return render_add_to_shelves_error("Select at least one content item and one shelf.") if content_ids.empty? || shelf_ids.empty?

    permitted_content_ids = policy_scope(Content).where(id: content_ids).pluck(:id)
    return render_add_to_shelves_error("One or more selected content items is unavailable.") unless permitted_content_ids.sort == content_ids.sort

    message = current_user.with_lock do
      active_shelf_ids = current_user.active_shelves.where(shelf_id: shelf_ids).pluck(:shelf_id)
      next unless active_shelf_ids.sort == shelf_ids.sort

      add_to_shelves_message(content_ids:, shelf_ids:)
    end
    return render_add_to_shelves_error("One or more selected shelves is no longer active.") unless message

    render_add_to_shelves_success(message)
  end

  def search
    authorize Content

    @target = params[:target]
    @selected_ids = params[:selected_ids].to_s.split(",")
    @metadata_type = policy_scope(MetadataType).find(params[:metadata_type_id])
    @selection_context = metadata_selection_context
    @component_id = metadata_component_id
    @metadatum_count = params[:metadatum_count].to_i.clamp(1, MAX_METADATA_SEARCH_RESULTS)
    @search_query = params[:search].to_s.strip

    escaped_query = ActiveRecord::Base.sanitize_sql_like(@search_query)
    metadata_scope = policy_scope(@metadata_type.metadata)
      .where("LOWER(metadata.name) LIKE LOWER(?)", "%#{escaped_query}%")
      .order(Arel.sql("LENGTH(metadata.name), metadata.name"))

    metadata_results = metadata_scope.limit(@metadatum_count + 1).to_a
    @show_more = metadata_results.length > @metadatum_count
    @metadata = metadata_results.first(@metadatum_count)

    new_metadatum = @metadata_type.metadata.build(user: current_user)
    exact_match_exists = policy_scope(@metadata_type.metadata)
      .where("LOWER(metadata.name) = LOWER(?)", @search_query)
      .exists?
    @can_add_metadatum = @selection_context == "content" &&
      params.fetch(:allow_create, "1") == "1" &&
      @search_query.present? &&
      policy(new_metadatum).create? &&
      !exact_match_exists

    respond_to do |format|
      format.turbo_stream
    end
  end

  def add_new_metadatum
    authorize Content
    @metadata_type = policy_scope(MetadataType).find(params[:metadata_type_id])
    @target = params[:target]
    @selection_context = "content"
    @component_id = metadata_component_id
    @input_name = metadata_input_name
    @metadatum = @metadata_type.metadata.build(
      name: params[:name].to_s.strip,
      user: current_user,
      under_review: !(current_user.admin? || current_user.intern_plus?)
    )
    authorize @metadatum, :create?

    respond_to do |format|
      if @metadatum.save
        format.turbo_stream { render "add_metadatum" }
      else
        format.turbo_stream { render "add_new_metadatum_error" }
      end
    end
  end

  def add_existing_metadatum
    authorize Content
    @target = params[:target]
    @metadata_type = policy_scope(MetadataType).find(params[:metadata_type_id])
    @selection_context = metadata_selection_context
    @component_id = metadata_component_id
    @input_name = metadata_input_name
    @metadatum = policy_scope(@metadata_type.metadata).find(params[:metadatum_id])
    authorize @metadatum, :show?

    respond_to do |format|
      format.turbo_stream { render "add_metadatum" }
    end
  end

  def new
    @content = current_user.contents.build
    authorize @content

    render partial: "contents/modal_form", locals: { content: @content } if turbo_frame_request?
  end

  def show
    authorize @content
    @previous_content, @next_content = preview_neighbors

    if turbo_frame_request?
      render partial: "contents/preview_modal", locals: {
        content: @content,
        previous_content: @previous_content,
        next_content: @next_content,
        navigation_token: params[:navigation]
      }
    end
  end

  def edit
    authorize @content

    render partial: "contents/modal_form", locals: { content: @content } if turbo_frame_request?
  end

  def create
    @content = current_user.contents.build
    authorize @content
    @content.assign_attributes(content_params)

    respond_to do |format|
      if @content.save
        format.turbo_stream do
          if modal_frame_request?
            flash[:notice] = "Content was successfully created."
            render turbo_stream: turbo_stream.refresh(request_id: nil)
          else
            redirect_to contents_path, notice: "Content was successfully created.", status: :see_other
          end
        end
        format.html { redirect_to contents_path, notice: "Content was successfully created." }
      else
        format.turbo_stream do
          if modal_frame_request?
            render turbo_stream: turbo_stream.replace(
              "modal",
              partial: "contents/modal_form",
              locals: { content: @content }
            ), status: :unprocessable_content
          else
            render :new, formats: :html, status: :unprocessable_content
          end
        end
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  def update
    authorize @content
    authorize @content, :replace_file? if replacement_file_requested?

    respond_to do |format|
      if @content.update(content_params)
        format.turbo_stream do
          if modal_frame_request?
            flash[:notice] = "Content was successfully updated."
            render turbo_stream: turbo_stream.refresh(request_id: nil)
          else
            redirect_to contents_path, notice: "Content was successfully updated.", status: :see_other
          end
        end
        format.html { redirect_to contents_path, notice: "Content was successfully updated.", status: :see_other }
      else
        format.turbo_stream do
          if modal_frame_request?
            render turbo_stream: turbo_stream.replace(
              "modal",
              partial: "contents/modal_form",
              locals: { content: @content }
            ), status: :unprocessable_content
          else
            render :edit, formats: :html, status: :unprocessable_content
          end
        end
        format.html { render :edit, status: :unprocessable_content }
      end
    end
  end

  def validate_file
    content = content_for_file_validation
    blob = create_uploaded_blob(params[:file]) if params[:file].present?
    content.file.attach(blob) if blob
    content.valid?

    if content.errors[:file].empty?
      render json: {
        signed_id: blob.signed_id,
        filename: content.file.filename.to_s
      }
    else
      blob&.purge
      render json: { errors: content.errors[:file] }, status: :unprocessable_content
    end
  end

  private

  def load_contents_table
    metadata_types = policy_scope(MetadataType).order(:order, :name)
    source = policy_scope(Content).includes(:user, metadata: :metadata_type)
    @table_definition = ContentTables::ContentsDefinition.new(
      source:,
      metadata_types:,
      update_path: table_contents_path,
      reset_path: reset_table_contents_path,
      selection_form_id: ADD_TO_SHELVES_FORM_ID
    )
    session.delete("contents_index_state")
    table = ContentTables::Coordinator.call(
      user: current_user,
      definition: @table_definition,
      params:,
      paginator: method(:paginate_contents)
    )
    @table_state = table.state
    @pagy = table.pagy
    @contents = table.records
    @navigation_token = table.navigation_token
  end

  def load_metadata_types
    @metadata_types = policy_scope(MetadataType)
      .order(:order, :name)
  end

  def load_active_shelves
    @active_shelves = current_user.active_shelves.includes(:shelf).ordered.map(&:shelf)
  end

  def set_content
    @content = policy_scope(Content).with_attached_file.find(params.expect(:id))
  end

  def content_params
    params.require(:content).permit(policy(@content).permitted_attributes)
  end

  def create_uploaded_blob(uploaded_file)
    ActiveStorage::Blob.create_and_upload!(
      io: uploaded_file,
      filename: uploaded_file.original_filename,
      content_type: uploaded_file.content_type
    )
  end

  def content_for_file_validation
    return new_content_for_file_validation unless params[:id].present?

    content = policy_scope(Content).find(params.expect(:id))
    authorize content, :replace_file?
    content.dup.tap { |candidate| candidate.id = content.id }
  end

  def new_content_for_file_validation
    current_user.contents.build.tap { |content| authorize content, :create? }
  end

  def replacement_file_requested?
    content_attributes = params[:content]
    content_attributes.respond_to?(:[]) && content_attributes[:file].present?
  end

  def preview_neighbors
    content_ids = ContentTables::PageNavigation.content_ids_for(
      user: current_user,
      token: params[:navigation]
    )
    current_index = content_ids.index(@content.id)
    return [ nil, nil ] unless current_index

    previous_id = content_ids[current_index - 1] unless current_index.zero?
    next_id = content_ids[current_index + 1]
    neighboring_contents = policy_scope(Content)
      .where(id: [ previous_id, next_id ].compact)
      .index_by(&:id)

    [ neighboring_contents[previous_id], neighboring_contents[next_id] ]
  end

  def metadata_selection_context
    params[:selection_context] == "filter" ? "filter" : "content"
  end

  def metadata_component_id
    requested_id = params[:component_id]
    return requested_id if requested_id.is_a?(String) && requested_id.match?(/\A[a-zA-Z0-9_-]+\z/)

    "#{@selection_context}-metadata-type-#{@metadata_type.id}"
  end

  def metadata_input_name
    if @selection_context == "filter"
      "filters[metadata_type:#{@metadata_type.id}][metadatum_ids][]"
    else
      "content[metadatum_ids][]"
    end
  end

  def modal_frame_request?
    request.headers["Turbo-Frame"] == "modal"
  end

  def paginate_contents(relation:, page:, per_page:)
    pagy(
      :offset,
      relation,
      limit: per_page,
      page:
    )
  end

  def table_locals
    {
      definition: @table_definition,
      state: @table_state,
      records: @contents,
      pagy: @pagy,
      navigation_token: @navigation_token
    }
  end

  def selected_ids(key)
    Array(params[key]).filter_map { |value| Integer(value, exception: false) }.uniq
  end

  def render_add_to_shelves_error(message)
    render_add_to_shelves_status(message, type: :error, status: :unprocessable_content)
  end

  def render_add_to_shelves_status(message, type:, status: :ok)
    render turbo_stream: turbo_stream.update(
      ADD_TO_SHELVES_STATUS_ID,
      partial: "contents/add_to_shelves_status",
      locals: { message:, type: }
    ), status:
  end

  def render_add_to_shelves_success(message)
    load_active_shelves
    load_contents_table

    render turbo_stream: [
      turbo_stream.replace(
        @table_definition.frame_id,
        partial: "content_tables/table_frame",
        locals: table_locals
      ),
      turbo_stream.replace(
        ADD_TO_SHELVES_FORM_ID,
        partial: "contents/add_to_shelves_form",
        locals: { definition: @table_definition, active_shelves: @active_shelves }
      ),
      turbo_stream.update(
        ADD_TO_SHELVES_STATUS_ID,
        partial: "contents/add_to_shelves_status",
        locals: { message:, type: :success }
      )
    ]
  end

  def add_to_shelves_message(content_ids:, shelf_ids:)
    requested_pairs = shelf_ids.product(content_ids)
    existing_pairs = ShelfContent
      .where(shelf_id: shelf_ids, content_id: content_ids)
      .pluck(:shelf_id, :content_id)
      .to_h { |pair| [ pair, true ] }
    missing_pairs = requested_pairs.reject { |pair| existing_pairs.key?(pair) }

    if missing_pairs.any?
      ShelfContent.insert_all(
        missing_pairs.map { |shelf_id, content_id| { shelf_id:, content_id: } },
        unique_by: :index_shelf_contents_on_shelf_id_and_content_id
      )
    end

    if missing_pairs.empty?
      "The selected content is already on the selected shelves."
    elsif missing_pairs.length < requested_pairs.length
      "Content was added to the selected shelves. Existing placements were skipped."
    else
      "Content was added to the selected shelves."
    end
  end
end
