class LibraryVersionsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library

  def new
    @library_version = build_library_version
    authorize @library_version

    render partial: "library_versions/modal_form" if turbo_frame_request?
  end

  def create
    @library_version = build_library_version(library_version_params)
    authorize @library_version

    @library_version = LibraryVersions::Create.call(
      library: @library,
      version_number: @library_version.version_number,
      user: current_user
    )

    respond_to do |format|
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
  end

  private

  def set_library
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
