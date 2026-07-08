class ContentsController < ApplicationController
  PER_PAGE_OPTIONS = [ 10, 20, 50, 100 ].freeze
  DEFAULT_PER_PAGE = 10
  METADATA_COLUMN_PREFIX = "metadata_type:"
  CONTENT_COLUMNS = [
    { key: "id", label: "ID", type: :content },
    { key: "title", label: "Title", type: :content },
    { key: "display_title", label: "Display title", type: :content },
    { key: "description", label: "Description", type: :content },
    { key: "year_of_publication", label: "Year of publication", type: :content },
    { key: "additional_notes", label: "Additional notes", type: :content },
    { key: "created_at", label: "Date created", type: :content },
    { key: "updated_at", label: "Date updated", type: :content },
    { key: "added_by", label: "Added by", type: :content }
  ].freeze
  DEFAULT_CONTENT_COLUMN_KEYS = %w[title created_at added_by].freeze

  before_action :authenticate_user!

  def index
    authorize Content

    @search_query = params[:q].to_s
    @per_page_options = PER_PAGE_OPTIONS
    @per_page = normalized_per_page
    @metadata_types = policy_scope(MetadataType).order(:order, :name)
    @content_columns = CONTENT_COLUMNS
    @metadata_columns = metadata_columns
    @available_columns = @content_columns + @metadata_columns
    @columns_present = columns_present?
    @selected_column_keys = selected_column_keys
    @selected_columns = @available_columns.select { |column| @selected_column_keys.include?(column[:key]) }
    @column_selection_params = column_selection_params

    contents = filtered_contents
    @pagy, @contents = pagy(:offset, contents, limit: @per_page)
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

  def filtered_contents
    contents = policy_scope(Content)
      .includes(:user, metadata: :metadata_type)
      .order(created_at: :desc)

    return contents if @search_query.blank?

    query = ActiveRecord::Base.sanitize_sql_like(@search_query)
    contents.where("contents.title LIKE ?", "%#{query}%")
  end

  def normalized_per_page
    per_page = params[:per_page].to_i

    PER_PAGE_OPTIONS.include?(per_page) ? per_page : DEFAULT_PER_PAGE
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
        metadata_type_id: metadata_type.id
      }
    end
  end

  def selected_column_keys
    return default_column_keys unless @columns_present

    requested_column_keys & available_column_keys
  end

  def columns_present?
    params[:columns_present].present? || params.key?(:columns)
  end

  def requested_column_keys
    Array(params[:columns]).filter_map { |column_key| column_key.to_s.presence }
  end

  def available_column_keys
    @available_columns.map { |column| column[:key] }
  end

  def default_column_keys
    DEFAULT_CONTENT_COLUMN_KEYS + @metadata_types.first(2).map { |metadata_type| metadata_column_key(metadata_type) }
  end

  def metadata_column_key(metadata_type)
    "#{METADATA_COLUMN_PREFIX}#{metadata_type.id}"
  end

  def column_selection_params
    return {} unless @columns_present

    column_params = { columns_present: "1" }
    column_params[:columns] = @selected_column_keys if @selected_column_keys.any?
    column_params
  end
end
