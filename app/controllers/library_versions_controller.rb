class LibraryVersionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library

  rescue_from Pundit::NotAuthorizedError do
    if request.format.json?
      render json: { error: "forbidden" }, status: :forbidden
    else
      user_not_authorized
    end
  end

  def new
    @library_version = build_library_version
    authorize @library_version

    render partial: "library_versions/modal_form" if turbo_frame_request?
  end

  def create
    @library_version = build_library_version(library_version_params)
    authorize @library_version

    if ActiveModel::Type::Boolean.new.cast(params[:build_previous_version])
      result = LibraryVersions::CreateWithBuild.call(
        library: @library, version_number: @library_version.version_number,
        expected_current_version_id: params[:expected_current_version_id], user: current_user
      )
      @library_version, @library_build = result.new_version, result.build
    else
      @library_version = LibraryVersions::Create.call(
        library: @library, version_number: @library_version.version_number, user: current_user
      )
    end

    respond_to do |format|
      format.json do
        render json: {
          new_version: { id: @library_version.id, version_number: @library_version.version_number },
          locked_version: { id: @library_version.previous_version_id,
            version_number: @library_version.previous_version.version_number },
          build: (@library_build ? { id: @library_build.id, generation: @library_build.generation, status: @library_build.status } : nil)
        }, status: :created
      end
      format.turbo_stream do
        redirect_to library_path(@library), notice: creation_notice, status: :see_other
      end
      format.html do
        redirect_to library_path(@library), notice: creation_notice, status: :see_other
      end
    end
  rescue ActiveRecord::RecordInvalid => error
    copy_validation_errors(error.record)
    render_invalid
  rescue LibraryBuilds::Error => error
    render json: { error: error.code, message: error.message }, status: :conflict
  end

  private

  def set_library
    authorize LibraryVersion, :create? if request.format.json?
    @library = policy_scope(Library).find(params.expect(:library_id))
  end

  def build_library_version(attributes = {})
    @library.library_versions.build(attributes.merge(user: current_user))
  end

  def library_version_params
    params.expect(library_version: [ :version_number ])
  end

  def copy_validation_errors(record)
    if record.is_a?(LibraryVersion) && record.new_record?
      @library_version = record
    else
      record.errors.full_messages.each do |message|
        @library_version.errors.add(:base, message)
      end
    end
  end

  def render_invalid
    respond_to do |format|
      format.json { render json: { errors: @library_version.errors.full_messages }, status: :unprocessable_content }
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "modal",
          partial: "library_versions/modal_form"
        ), status: :unprocessable_content
      end
      format.html { render :new, status: :unprocessable_content }
    end
  end

  def creation_notice
    "Library version #{@library_version.version_number} was successfully created."
  end
end
