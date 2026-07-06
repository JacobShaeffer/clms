class MetadataController < ApplicationController
  METADATA_VALUES_PAGE_SIZE = 5
  MAX_METADATA_VALUES_LIMIT = 100

  before_action :authenticate_user!
  before_action :set_metadata_type
  before_action :set_metadatum, only: %i[ show edit update destroy toggle_review tagged_items delete_confirmation ]

  # GET /metadata_types/1/metadata
  def index
    authorize @metadata_type, :metadata_values?

    @metadata = policy_scope(@metadata_type.metadata)
  end

  # GET /metadata_types/1/metadata/1
  def show
    authorize @metadatum
  end

  # GET /metadata_types/1/metadata/new
  def new
    @metadatum = @metadata_type.metadata.build(under_review: true)
    authorize @metadatum

    render partial: "metadata/modal_form", locals: metadatum_form_locals if turbo_frame_request?
  end

  # GET /metadata_types/1/metadata/1/edit
  def edit
    authorize @metadatum

    render partial: "metadata/modal_form", locals: metadatum_form_locals if turbo_frame_request?
  end

  # POST /metadata_types/1/metadata
  def create
    @metadatum = current_user.metadata.build(metadata_type: @metadata_type, under_review: true)
    authorize @metadatum
    @metadatum.assign_attributes(metadatum_params)

    respond_to do |format|
      if @metadatum.save
        format.turbo_stream { render_metadata_values_update }
        format.html { redirect_to metadata_types_path, notice: "Metadatum was successfully created." }
        format.json { render :show, status: :created, location: metadata_type_metadatum_path(@metadata_type, @metadatum) }
      else
        format.turbo_stream { render_metadatum_form_error }
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @metadatum.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /metadata_types/1/metadata/1
  def update
    authorize @metadatum

    respond_to do |format|
      if @metadatum.update(metadatum_params)
        format.turbo_stream { render_metadata_values_update }
        format.html { redirect_to metadata_types_path, notice: "Metadatum was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: metadata_type_metadatum_path(@metadata_type, @metadatum) }
      else
        format.turbo_stream { render_metadatum_form_error }
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @metadatum.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /metadata_types/1/metadata/1
  def destroy
    authorize @metadatum

    @metadatum.destroy!

    respond_to do |format|
      format.turbo_stream { render_metadata_values_update }
      format.html { redirect_to metadata_types_path, notice: "Metadatum was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  # PATCH /metadata_types/1/metadata/1/toggle_review
  def toggle_review
    authorize @metadatum

    @metadatum.update!(under_review: !@metadatum.under_review?)

    respond_to do |format|
      format.turbo_stream { render_metadata_values_update(close_modal: false) }
      format.html { redirect_to metadata_types_path, status: :see_other }
      format.json { render :show, status: :ok, location: metadata_type_metadatum_path(@metadata_type, @metadatum) }
    end
  end

  # GET /metadata_types/1/metadata/1/tagged_items
  def tagged_items
    authorize @metadatum

    render partial: "metadata/tagged_items_modal", locals: { metadatum: @metadatum }
  end

  # GET /metadata_types/1/metadata/1/delete_confirmation
  def delete_confirmation
    authorize @metadatum

    render partial: "metadata/delete_confirmation_modal", locals: {
      metadata_type: @metadata_type,
      metadatum: @metadatum,
      frame_params: frame_params
    }
  end

  private
    def set_metadata_type
      @metadata_type = MetadataType.find(params.expect(:metadata_type_id))
    end

    def set_metadatum
      @metadatum = @metadata_type.metadata.find(params.expect(:id))
    end

    def metadatum_params
      params.require(:metadatum).permit(policy(@metadatum).permitted_attributes)
    end

    def metadatum_form_locals
      {
        metadata_type: @metadata_type,
        metadatum: @metadatum,
        url: metadatum_form_url
      }
    end

    def metadatum_form_url
      if @metadatum.persisted?
        metadata_type_metadatum_path(@metadata_type, @metadatum, frame_params)
      else
        metadata_type_metadata_path(@metadata_type, frame_params)
      end
    end

    def render_metadatum_form_error
      render turbo_stream: turbo_stream.update(
        "modal",
        partial: "metadata/modal_form",
        locals: metadatum_form_locals
      ), status: :unprocessable_entity
    end

    def render_metadata_values_update(close_modal: true)
      streams = []
      streams << turbo_stream.update("modal", "") if close_modal
      streams << turbo_stream.replace(
        helpers.dom_id(@metadata_type, :metadata_values),
        partial: "metadata_types/metadata_values",
        locals: metadata_values_locals
      )
      streams << turbo_stream.update(
        helpers.dom_id(@metadata_type, :metadata_count),
        @metadata_type.metadata.count.to_s
      )

      render turbo_stream: streams
    end

    def metadata_values_locals
      search_query = params[:q].to_s
      review_filter = normalized_metadata_review_filter
      limit = metadata_values_limit
      metadata_values = filtered_metadata_values(search_query, review_filter)
      count = metadata_values.count

      {
        metadata_type: @metadata_type,
        metadata_values: metadata_values.limit(limit),
        metadata_values_count: count,
        metadata_values_limit: limit,
        metadata_values_next_limit: [limit + METADATA_VALUES_PAGE_SIZE, count].min,
        search_query: search_query,
        review_filter: review_filter
      }
    end

    def filtered_metadata_values(search_query, review_filter)
      metadata_values = @metadata_type.metadata.order(:name)

      if search_query.present?
        query = ActiveRecord::Base.sanitize_sql_like(search_query)
        metadata_values = metadata_values.where("metadata.name LIKE ?", "%#{query}%")
      end

      case review_filter
      when "under_review"
        metadata_values.where(under_review: true)
      when "reviewed"
        metadata_values.where(under_review: false)
      else
        metadata_values
      end
    end

    def metadata_values_limit
      limit = params[:limit].to_i
      limit = METADATA_VALUES_PAGE_SIZE if limit < METADATA_VALUES_PAGE_SIZE
      [limit, MAX_METADATA_VALUES_LIMIT].min
    end

    def normalized_metadata_review_filter
      case params[:status].to_s
      when "under_review", "UR", "true"
        "under_review"
      when "reviewed", "R", "false"
        "reviewed"
      else
        "all"
      end
    end

    def frame_params
      {
        q: params[:q].presence,
        status: params[:status].presence,
        limit: params[:limit].presence
      }.compact
    end
end
