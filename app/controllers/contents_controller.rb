class ContentsController < ApplicationController
  MAX_METADATA_SEARCH_RESULTS = 100

  before_action :authenticate_user!
  before_action :load_metadata_types, only: %i[new create]

  def index
    authorize Content
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

  def search
    authorize Content

    @target = params[:target]
    @selected_ids = params[:selected_ids].to_s.split(",")
    @metadata_type = policy_scope(MetadataType).find(params[:metadata_type_id])
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
    @can_add_metadatum = @search_query.present? && policy(new_metadatum).create? && !exact_match_exists

    respond_to do |format|
      format.turbo_stream
    end
  end

  def add_new_metadatum
    authorize Content
    @metadata_type = policy_scope(MetadataType).find(params[:metadata_type_id])
    @target = params[:target]
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

  def load_contents_table
    metadata_types = policy_scope(MetadataType).order(:order, :name)
    source = policy_scope(Content).includes(:user, metadata: :metadata_type)
    @table_definition = ContentTables::ContentsDefinition.new(
      source:,
      metadata_types:,
      update_path: table_contents_path,
      reset_path: reset_table_contents_path
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
  end

  def load_metadata_types
    @metadata_types = policy_scope(MetadataType)
      .order(:order, :name)
  end

  def content_params
    params.require(:content).permit(policy(@content).permitted_attributes)
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
      pagy: @pagy
    }
  end
end
