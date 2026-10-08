class LibraryAssetsController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_library_asset_access
  before_action :load_asset_filters
  before_action :set_library_asset, only: %i[ show edit update destroy delete_confirmation ]

  # GET /library_assets or /library_assets.json
  def index
    load_library_assets
  end

  # GET /library_assets/1 or /library_assets/1.json
  def show
    render partial: "library_assets/show_modal", locals: { library_asset: @library_asset } if turbo_frame_request?
  end

  # GET /library_assets/new
  def new
    @library_asset = current_user.library_assets.build

    render partial: "library_assets/modal_form", locals: { library_asset: @library_asset } if turbo_frame_request?
  end

  # GET /library_assets/1/edit
  def edit
    render partial: "library_assets/modal_form", locals: { library_asset: @library_asset } if turbo_frame_request?
  end

  # POST /library_assets or /library_assets.json
  def create
    @library_asset = current_user.library_assets.build(library_asset_params)

    respond_to do |format|
      if @library_asset.save
        format.turbo_stream do
          render_asset_results
        end
        format.html { redirect_to @library_asset, notice: "Library asset was successfully created." }
        format.json { render :show, status: :created, location: @library_asset }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "modal",
            partial: "library_assets/modal_form",
            locals: { library_asset: @library_asset }
          ), status: :unprocessable_content
        end
        format.html { render :new, status: :unprocessable_content }
        format.json { render json: @library_asset.errors, status: :unprocessable_content }
      end
    end
  end

  # PATCH/PUT /library_assets/1 or /library_assets/1.json
  def update
    respond_to do |format|
      if @library_asset.update(library_asset_params)
        format.turbo_stream do
          render_asset_results
        end
        format.html { redirect_to @library_asset, notice: "Library asset was successfully updated.", status: :see_other }
        format.json { render :show, status: :ok, location: @library_asset }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "modal",
            partial: "library_assets/modal_form",
            locals: { library_asset: @library_asset }
          ), status: :unprocessable_content
        end
        format.html { render :edit, status: :unprocessable_content }
        format.json { render json: @library_asset.errors, status: :unprocessable_content }
      end
    end
  end

  # DELETE /library_assets/1 or /library_assets/1.json
  def destroy
    @library_asset.destroy!

    respond_to do |format|
      format.turbo_stream do
        render_asset_results
      end
      format.html { redirect_to library_assets_path, notice: "Library asset was successfully destroyed.", status: :see_other }
      format.json { head :no_content }
    end
  end

  # GET /library_assets/1/delete_confirmation
  def delete_confirmation
    render partial: "library_assets/delete_confirmation_modal", locals: { library_asset: @library_asset }
  end

  private
    def authorize_library_asset_access
      authorize LibraryAsset
    end

    def load_asset_filters
      values = action_name == "index" ? params : params[:library_asset_filters]
      values = {} unless values.respond_to?(:permit)
      @query = values[:q].is_a?(String) ? values[:q].strip : ""
      @language = LibraryAsset::LANGUAGES.include?(values[:language]) ? values[:language] : ""
      @asset_type = LibraryAsset::ASSET_TYPES.include?(values[:asset_type]) ? values[:asset_type] : ""
      @asset_filter_context = { q: @query.presence, language: @language.presence, asset_type: @asset_type.presence }.compact
    end

    def load_library_assets
      @library_assets = policy_scope(LibraryAsset).with_attached_image.with_attached_design_files.order(:id)
      if @query.present?
        @library_assets = @library_assets.where("library_assets.name ILIKE ?", "%#{LibraryAsset.sanitize_sql_like(@query)}%")
      end
      @library_assets = @library_assets.where(language: @language) if @language.present?
      @library_assets = @library_assets.where(asset_type: @asset_type) if @asset_type.present?
    end

    def render_asset_results
      load_library_assets
      streams = [
        turbo_stream.update("modal", ""),
        turbo_stream.update("library_asset_results", partial: "library_assets/results")
      ]
      if action_name == "update"
        streams << turbo_stream.replace(
          @library_asset, partial: "library_assets/library_asset", locals: { library_asset: @library_asset }
        )
      end
      render turbo_stream: streams
    end

    # Use callbacks to share common setup or constraints between actions.
    def set_library_asset
      @library_asset = LibraryAsset.find(params.expect(:id))
    end

    # Only allow a list of trusted parameters through.
    def library_asset_params
      params.expect(library_asset: [ :name, :language, :asset_type, :image, :design_files ])
    end
end
