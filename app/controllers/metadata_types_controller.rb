class MetadataTypesController < ApplicationController
  before_action :set_metadata_type, only: %i[ show edit update destroy ]

  # GET /metadata_types or /metadata_types.json
  def index
    @metadata_types = MetadataType.all
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
