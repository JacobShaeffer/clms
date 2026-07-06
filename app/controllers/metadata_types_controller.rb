class MetadataTypesController < ApplicationController
  METADATA_VALUES_PAGE_SIZE = 5
  MAX_METADATA_VALUES_LIMIT = 100

  before_action :authenticate_user!
  before_action :set_metadata_type, only: %i[ show edit update destroy metadata_values ]

  # GET /metadata_types or /metadata_types.json
  def index
    authorize MetadataType

    @metadata_types = policy_scope(MetadataType)
    @metadata_counts = Metadatum.where(metadata_type_id: @metadata_types.map(&:id)).group(:metadata_type_id).count
  end

  # GET /metadata_types/1/metadata_values
  def metadata_values
    authorize @metadata_type

    @metadata_search_query = params[:q].to_s
    @metadata_review_filter = normalized_metadata_review_filter
    @metadata_values_limit = metadata_values_limit

    metadata_values = filtered_metadata_values

    @metadata_values_count = metadata_values.count
    @metadata_values_next_limit = [@metadata_values_limit + METADATA_VALUES_PAGE_SIZE, @metadata_values_count].min
    @metadata_values = metadata_values.limit(@metadata_values_limit)

    render partial: "metadata_types/metadata_values", locals: {
      metadata_type: @metadata_type,
      metadata_values: @metadata_values,
      metadata_values_count: @metadata_values_count,
      metadata_values_limit: @metadata_values_limit,
      metadata_values_next_limit: @metadata_values_next_limit,
      search_query: @metadata_search_query,
      review_filter: @metadata_review_filter
    }
  end

  # GET /metadata_types/1 or /metadata_types/1.json
  def show
    authorize @metadata_type
  end

  # GET /metadata_types/new
  def new
    @metadata_type = MetadataType.new
    authorize @metadata_type

    render partial: "metadata_types/modal_form", locals: { metadata_type: @metadata_type } if turbo_frame_request?
  end

  # GET /metadata_types/1/edit
  def edit
    authorize @metadata_type
  end

  # POST /metadata_types or /metadata_types.json
  def create
    @metadata_type = current_user.metadata_types.build
    authorize @metadata_type
    @metadata_type.assign_attributes(metadata_type_params)

    respond_to do |format|
      if @metadata_type.save
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update("modal", ""),
            turbo_stream.prepend(
              "metadata-types",
              partial: "metadata_types/metadata_type",
              locals: {
                metadata_type: @metadata_type,
                metadata_counts: { @metadata_type.id => 0 }
              }
            )
          ]
        end
        format.html { redirect_to @metadata_type, notice: "Metadata type was successfully created." }
        format.json { render :show, status: :created, location: @metadata_type }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.update(
            "modal",
            partial: "metadata_types/modal_form",
            locals: { metadata_type: @metadata_type }
          ), status: :unprocessable_entity
        end
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @metadata_type.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /metadata_types/1 or /metadata_types/1.json
  def update
    authorize @metadata_type

    respond_to do |format|
      if @metadata_type.update(metadata_type_params)
        format.html { redirect_to @metadata_type, notice: "Metadata type was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @metadata_type }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @metadata_type.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /metadata_types/1 or /metadata_types/1.json
  def destroy
    authorize @metadata_type

    @metadata_type.destroy!

    respond_to do |format|
      format.html { redirect_to metadata_types_path, notice: "Metadata type was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_metadata_type
      @metadata_type = MetadataType.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def metadata_type_params
      params.require(:metadata_type).permit(policy(@metadata_type).permitted_attributes)
    end

    def filtered_metadata_values
      metadata_values = @metadata_type.metadata.order(:name)

      if @metadata_search_query.present?
        query = ActiveRecord::Base.sanitize_sql_like(@metadata_search_query)
        metadata_values = metadata_values.where("metadata.name LIKE ?", "%#{query}%")
      end

      case @metadata_review_filter
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
end
