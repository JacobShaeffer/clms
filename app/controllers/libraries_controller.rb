class LibrariesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library, only: :show

  def index
    authorize Library

    @libraries = ordered_libraries
  end

  def show
    authorize @library

    @root_folders = @library.library_folders.roots.order(:name, :id).load
  end

  def new
    @library = current_user.libraries.build
    authorize @library

    render partial: "libraries/modal_form", locals: { library: @library } if turbo_frame_request?
  end

  def create
    @library = current_user.libraries.build(library_params)
    authorize @library

    respond_to do |format|
      if @library.save
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.update("modal", ""),
            turbo_stream.update(
              "libraries",
              partial: "libraries/table_rows",
              locals: { libraries: ordered_libraries }
            )
          ]
        end
        format.html { redirect_to @library, notice: "Library was successfully created." }
      else
        format.turbo_stream do
          render turbo_stream: turbo_stream.replace(
            "modal",
            partial: "libraries/modal_form",
            locals: { library: @library }
          ), status: :unprocessable_content
        end
        format.html { render :new, status: :unprocessable_content }
      end
    end
  end

  private

  def set_library
    @library = policy_scope(Library).find(params.expect(:id))
  end

  def ordered_libraries
    policy_scope(Library)
      .includes(:current_version)
      .order(:name, :id)
      .load
  end

  def library_params
    params.expect(library: [ :name ])
  end
end
