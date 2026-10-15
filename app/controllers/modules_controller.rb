class ModulesController < ApplicationController
  before_action :authenticate_user!
  before_action :load_module_filters
  before_action :set_library_module, only: %i[ show edit update destroy delete_confirmation ]

  def index
    authorize LibraryModule
    load_library_modules
  end

  def show
    render partial: "modules/show_modal", locals: { library_module: @library_module } if turbo_frame_request?
  end

  def new
    @library_module = current_user.library_modules.build
    authorize @library_module
    load_icon_options

    render partial: "modules/modal_form", locals: { library_module: @library_module } if turbo_frame_request?
  end

  def create
    @library_module = current_user.library_modules.build(library_module_params)
    authorize @library_module
    load_icon_options

    respond_to do |format|
      if @library_module.save
        format.turbo_stream { render_module_results }
        format.html do
          redirect_to module_path(@library_module), notice: "Module was successfully created."
        end
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "modal",
            partial: "modules/modal_form",
            locals: { library_module: @library_module }
          ), status: :unprocessable_content
        end
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  def edit
    load_icon_options

    render partial: "modules/modal_form", locals: { library_module: @library_module } if turbo_frame_request?
  end

  def update
    load_icon_options

    respond_to do |format|
      if @library_module.update(library_module_params)
        format.turbo_stream { render_module_results }
        format.html do
          redirect_to module_path(@library_module), notice: "Module was successfully updated.", status: :see_other
        end
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "modal",
            partial: "modules/modal_form",
            locals: { library_module: @library_module }
          ), status: :unprocessable_content
        end
        format.html { render :edit, status: :unprocessable_content }
      end
    end
  end

  def destroy
    @library_module.destroy!

    respond_to do |format|
      format.turbo_stream { render_module_results }
      format.html do
        redirect_to modules_path, notice: "Module was successfully destroyed.", status: :see_other
      end
    end
  end

  def delete_confirmation
    render partial: "modules/delete_confirmation_modal", locals: { library_module: @library_module }
  end

  private

  def set_library_module
    @library_module = LibraryModule.find(params.expect(:id))
    authorize @library_module
  end

  def load_module_filters
    values = action_name == "index" ? params : params[:module_filters]
    values = {} unless values.respond_to?(:permit)
    @query = values[:q].is_a?(String) ? values[:q].strip : ""
    @module_filter_context = { q: @query.presence }.compact
  end

  def load_library_modules
    @library_modules = policy_scope(LibraryModule)
      .includes(icon: { image_attachment: :blob })
      .order(LibraryModule.arel_table[:name].lower, :id)
    return if @query.blank?

    @library_modules = @library_modules.where(
      "library_modules.name ILIKE ?",
      "%#{LibraryModule.sanitize_sql_like(@query)}%"
    )
  end

  def load_icon_options
    @icon_options = policy_scope(LibraryAsset).with_attached_image.to_a.sort_by do |asset|
      [ asset.display_name.downcase, asset.id ]
    end
  end

  def render_module_results
    load_library_modules
    render turbo_stream: [
      turbo_stream.update("modal", ""),
      turbo_stream.update("module_results", partial: "modules/results")
    ]
  end

  def library_module_params
    params.expect(library_module: %i[ name folder_name icon_id ])
  end
end
