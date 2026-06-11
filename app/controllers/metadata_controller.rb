class MetadataController < ApplicationController
  before_action :set_metadatum, only: %i[ show edit update destroy ]

  # GET /metadata or /metadata.json
  def index
    @metadata = Metadatum.all
  end

  # GET /metadata/1 or /metadata/1.json
  def show
  end

  # GET /metadata/new
  def new
    @metadatum = Metadatum.new
  end

  # GET /metadata/1/edit
  def edit
  end

  # POST /metadata or /metadata.json
  def create
    @metadatum = Metadatum.new(metadatum_params)

    respond_to do |format|
      if @metadatum.save
        format.html { redirect_to @metadatum, notice: "Metadatum was successfully created." }
        format.json { render :show, status: :created, location: @metadatum }
      else
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @metadatum.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /metadata/1 or /metadata/1.json
  def update
    respond_to do |format|
      if @metadatum.update(metadatum_params)
        format.html { redirect_to @metadatum, notice: "Metadatum was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @metadatum }
      else
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @metadatum.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /metadata/1 or /metadata/1.json
  def destroy
    @metadatum.destroy!

    respond_to do |format|
      format.html { redirect_to metadata_path, notice: "Metadatum was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  private
    # Use callbacks to share common setup or constraints between actions.
    def set_metadatum
      @metadatum = Metadatum.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def metadatum_params
      params.fetch(:metadatum, {})
    end
end
