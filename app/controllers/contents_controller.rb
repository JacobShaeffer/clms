class ContentsController < ApplicationController
  PER_PAGE_OPTIONS = [ 10, 20, 50, 100 ].freeze
  DEFAULT_PER_PAGE = 10
  METADATA_COLUMN_PREFIX = "metadata_type:"
  CONTENT_COLUMNS = [
    { key: "id", label: "ID", type: :content, filter: :number },
    { key: "title", label: "Title", type: :content, filter: :text },
    { key: "display_title", label: "Display title", type: :content, filter: :text },
    { key: "description", label: "Description", type: :content, filter: :text },
    { key: "year_of_publication", label: "Year of publication", type: :content, filter: :number },
    { key: "additional_notes", label: "Additional notes", type: :content, filter: :number },
    { key: "created_at", label: "Date created", type: :content, filter: :date },
    { key: "updated_at", label: "Date updated", type: :content, filter: :date },
    { key: "added_by", label: "Added by", type: :content, filter: :text }
  ].freeze
  DEFAULT_CONTENT_COLUMN_KEYS = %w[title created_at added_by].freeze

  before_action :authenticate_user!

  def index
    authorize Content
    load_contents_index(reset: true)
  end

  def table
    authorize Content
    load_contents_index

    render partial: "contents/table_frame", locals: table_locals
  end

  def add_new_metadatum
    authorize Content
    # Add a new metadatum to the database while createing a content record
    @metadata_type = MetadataType.find(params[:metadata_type_id])
    @target = params[:target]
    @metadatum = @metadata_type.metadata.create(name: params[:name], user: current_user)
    @metadatum.needs_review = false if current_user.admin? || current_user.intern_plus?
    respond_to do |format|
      if @metadatum.save
        format.turbo_stream { render "add_metadatum" }
      else
        @target += "_container"
        format.turbo_stream { render "add_new_metadatum_error" }
      end
    end
  end

  def add_existing_metadatum
    authorize Content
    # Add a new metadatum to the database while createing a content record
    @target = params[:target]
    @metadata_type = MetadataType.find(params[:metadata_type_id])
    @metadatum = @metadata_type.metadata.find(params[:metadatum_id])
    respond_to do |format|
      format.turbo_stream { render "add_metadatum" }
    end
  end

  def new
    @content = current_user.contents.build
    authorize @content

    render partial: "contents/modal_form", locals: { content: @content } if turbo_frame_request?
  end

  def create
    @content = current_user.contents.build
    authorize @content
    @content.assign_attributes(content_params)

    if @content.save
      redirect_to contents_path, notice: "Content was successfully created."
    else
      render :new, status: :unprocessable_content
    end
  end

  private

  def load_contents_index(reset: false)
    @metadata_types = policy_scope(MetadataType).order(:order, :name)
    @content_columns = CONTENT_COLUMNS
    @metadata_columns = metadata_columns
    @available_columns = @content_columns + @metadata_columns
    @per_page_options = PER_PAGE_OPTIONS
    @index_state = contents_index_state
    reset ? @index_state.reset! : @index_state.update!
    @search_query = @index_state.q
    @filters = @index_state.filters
    @per_page = @index_state.per_page
    @columns_present = @index_state.columns_present?
    @selected_column_keys = @index_state.selected_column_keys
    @selected_columns = @available_columns.select { |column| @selected_column_keys.include?(column[:key]) }
    @sort_column = @index_state.sort_column
    @sort_direction = @index_state.sort_direction
    @sorted_column = @selected_columns.find { |column| column[:key] == @sort_column }

    contents = filtered_contents
    @pagy, @contents = pagy(:offset, contents, limit: @per_page)
  end

  def filtered_contents
    contents = policy_scope(Content)
      .includes(:user, metadata: :metadata_type)

    contents = apply_quick_search(contents)
    contents = apply_advanced_filters(contents)

    Contents::Sorter.call(
      relation: contents,
      column: @sorted_column,
      direction: @sort_direction
    )
  end

  def apply_quick_search(contents)
    return contents if @search_query.blank?

    query = ActiveRecord::Base.sanitize_sql_like(@search_query)
    contents.where("contents.title LIKE ?", "%#{query}%")
  end

  def apply_advanced_filters(contents)
    @filters.each do |column_key, filter|
      column = @available_columns.find { |available_column| available_column[:key] == column_key }
      next if column.blank?

      contents = if column[:type] == :metadata
        apply_metadata_filter(contents, column, filter)
      else
        apply_content_filter(contents, column, filter)
      end
    end

    contents
  end

  def apply_content_filter(contents, column, filter)
    case column[:filter]
    when :date
      apply_date_filter(contents, column[:key], filter)
    when :number
      apply_number_filter(contents, column[:key], filter)
    else
      apply_text_filter(contents, column[:key], filter)
    end
  end

  def apply_metadata_filter(contents, column, filter)
    value = filter["value"].to_s
    return contents if value.blank?

    query = ActiveRecord::Base.sanitize_sql_like(value)
    matching_content_ids = Content.joins(:metadata)
      .where("metadata.metadata_type_id = ?", column[:metadata_type_id])
      .where("metadata.name LIKE ?", "%#{query}%")
      .select(:id)

    contents.where(id: matching_content_ids)
  end

  def apply_text_filter(contents, column_key, filter)
    value = filter["value"].to_s
    return contents if value.blank?

    query = ActiveRecord::Base.sanitize_sql_like(value)

    if column_key == "added_by"
      contents.joins(:user).where("users.name LIKE ? OR users.email LIKE ?", "%#{query}%", "%#{query}%")
    else
      contents.where("contents.#{column_key} LIKE ?", "%#{query}%")
    end
  end

  def apply_number_filter(contents, column_key, filter)
    value = Integer(filter["value"], exception: false)
    return contents if value.blank?

    contents.where(contents: { column_key => value })
  end

  def apply_date_filter(contents, column_key, filter)
    from_date = parse_filter_date(filter["from"])
    to_date = parse_filter_date(filter["to"])

    contents = contents.where("contents.#{column_key} >= ?", from_date.beginning_of_day) if from_date
    contents = contents.where("contents.#{column_key} <= ?", to_date.end_of_day) if to_date

    contents
  end

  def content_params
    params.require(:content).permit(policy(@content).permitted_attributes)
  end

  def metadata_columns
    @metadata_types.map do |metadata_type|
      {
        key: metadata_column_key(metadata_type),
        label: metadata_type.name,
        type: :metadata,
        metadata_type_id: metadata_type.id,
        filter: :text
      }
    end
  end

  def default_column_keys
    DEFAULT_CONTENT_COLUMN_KEYS + @metadata_types.first(2).map { |metadata_type| metadata_column_key(metadata_type) }
  end

  def metadata_column_key(metadata_type)
    "#{METADATA_COLUMN_PREFIX}#{metadata_type.id}"
  end

  def contents_index_state
    Contents::IndexState.new(
      session: session,
      params: params,
      available_columns: @available_columns,
      default_column_keys: default_column_keys,
      per_page_options: PER_PAGE_OPTIONS,
      default_per_page: DEFAULT_PER_PAGE
    )
  end

  def table_locals
    {
      contents: @contents,
      selected_columns: @selected_columns,
      pagy: @pagy,
      sort_column: @sort_column,
      sort_direction: @sort_direction
    }
  end

  def parse_filter_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError
    nil
  end
end
