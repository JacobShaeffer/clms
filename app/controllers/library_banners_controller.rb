class LibraryBannersController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library
  before_action :authorize_banner_update
  before_action :load_banner_assets

  def edit
    render partial: "library_banners/modal_form" if turbo_frame_request?
  end

  def update
    banner = selected_banner
    unless banner
      @library.errors.add(:banner, "is not available")
      return render_invalid
    end

    return render_invalid unless @library.update(banner:)

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.update("modal", ""),
          turbo_stream.replace(
            helpers.dom_id(@library, :banner),
            partial: "libraries/banner",
            locals: { library: @library }
          )
        ]
      end
      format.html do
        redirect_to library_path(@library), notice: "Banner image was successfully updated.", status: :see_other
      end
    end
  end

  private

  def set_library
    @library = policy_scope(Library).find(params.expect(:library_id))
  end

  def authorize_banner_update
    authorize @library, :update_banner?
  end

  def load_banner_assets
    @banner_asset_scope = policy_scope(LibraryAsset).where(asset_type: "Banner")
    @banner_assets = @banner_asset_scope.with_attached_image.to_a.sort_by do |asset|
      [ asset.display_name.downcase, asset.id ]
    end
  end

  def selected_banner
    banner_id = Integer(library_params[:banner_id], exception: false)
    return unless banner_id

    @banner_asset_scope.find_by(id: banner_id)
  end

  def library_params
    values = params[:library]
    return ActionController::Parameters.new unless values.respond_to?(:permit)

    values.permit(:banner_id)
  end

  def render_invalid
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "modal",
          partial: "library_banners/modal_form"
        ), status: :unprocessable_content
      end
      format.html { render :edit, status: :unprocessable_content }
    end
  end
end
