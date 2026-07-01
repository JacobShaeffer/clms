class MetadataTypesController < ApplicationController
  before_action :set_metadata_type, only: %i[ show edit update destroy ]

  # GET /metadata_types or /metadata_types.json
  def index
    @open_accordions = if params.key?(:oa)
      Array(params[:oa]).reject(&:blank?).map(&:to_i)
    else
      []
    end

    @metadata_type_searches = {}
    if params[:s].is_a?(ActionController::Parameters)
      params[:s].each do |metadata_type_id, query|
        next unless query.is_a?(String)

        @metadata_type_searches[metadata_type_id.to_i] = query
      end
    end

    @metadata_type_review_filters = {}
    if params[:f].is_a?(ActionController::Parameters)
      params[:f].each do |metadata_type_id, filter|
        next unless filter.is_a?(String)

        @metadata_type_review_filters[metadata_type_id.to_i] = filter
      end
    end

    @metadata_type_metadata_counts = {}
    @metadata_type_metadata = {}
    @metadata_type_modal = ""
    @metadatum_modal = ""


    # Get the metadata_types and the associated metadata_values
    # only get metadata_values for only the open metadata_types
    # only the metadata_values that match the search criteria
    # only the first 5 metadata_values unless a metadata_count is specified
    @metadata_types = MetadataType.includes(:metadata).all
    @metadata_types_values = {}
    @open_accordions.each do |metadata_type_id|
      metadata_type_values = MetadataType.find(metadata_type_id).metadata
      metadata_values_limit = 5
      if @metadata_type_searches.key?(metadata_type_id)
        query = ActiveRecord::Base.sanitize_sql_like(@metadata_type_searches[metadata_type_id])
        metadata_type_values = metadata_type_values.where("name LIKE ?", "%#{query}%")
      end
      if @metadata_type_review_filters.key?(metadata_type_id)
        query = @metadata_type_review_filters[metadata_type_id] == "true" ? true : false
        metadata_type_values = metadata_type_values.where(under_review: query)
      end
      if @metadata_type_metadata_counts.key?(metadata_type_id)
        metadata_values_limit = @metadata_type_metadata_counts[metadata_type_id]
        metadata_values_limit = metadata_values_limit.to_i
      end
      @metadata_types_values[metadata_type_id] = metadata_type_values.limit(metadata_values_limit)
    end
  end

  # GET /metadata_types/1 or /metadata_types/1.json
  def show
  end

  # GET /metadata_types/new
  def new
    @metadata_type = MetadataType.new
  end

  # GET /metadata_types/1/edit
  def edit
  end

  # POST /metadata_types or /metadata_types.json
  def create
    @metadata_type = MetadataType.new(metadata_type_params)

    respond_to do |format|
      if @metadata_type.save
        format.html { redirect_to @metadata_type, notice: "Metadata type was successfully created." }
        format.json { render :show, status: :created, location: @metadata_type }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @metadata_type.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /metadata_types/1 or /metadata_types/1.json
  def update
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
      params.fetch(:metadata_type, {})
    end
end
