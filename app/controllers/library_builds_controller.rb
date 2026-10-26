class LibraryBuildsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_version

  rescue_from Pundit::NotAuthorizedError do
    render json: { error: "forbidden" }, status: :forbidden
  end
  rescue_from ActiveRecord::RecordNotFound do
    render json: { error: "not_found" }, status: :not_found
  end
  rescue_from LibraryBuilds::Error do |error|
    render json: { error: error.code, message: error.message }, status: :conflict
  end

  def create
    authorize LibraryBuild, :create?
    @build = LibraryBuilds::Request.call(library_version: @version, user: current_user)
    render json: build_payload, status: :accepted
  end

  def show
    authorize LibraryBuild, :show?
    @build = @version.library_build || raise(ActiveRecord::RecordNotFound)
    render json: build_payload
  end

  def download
    authorize LibraryBuild, :download?
    @build = @version.library_build || raise(ActiveRecord::RecordNotFound)
    file = @build.with_lock do
      raise LibraryBuilds::Error.new("No completed export is available.", code: "output_not_ready") unless @build.published?

      File.open(LibraryBuilds::Storage.new(@build).archive_path, "rb")
    end
    response.headers["Content-Type"] = "application/zip"
    response.headers["Content-Disposition"] = "attachment; filename=\"library-version-#{@version.id}.zip\""
    response.headers["Content-Length"] = file.size.to_s
    response.headers["Cache-Control"] = "no-store"
    self.response_body = LibraryBuilds::ArchiveBody.new(file)
  rescue Errno::ENOENT
    render json: { error: "output_missing", message: "Rebuild this version to restore its export." }, status: :conflict
  end

  private

  def set_version
    # Authorize before lookup so lower roles cannot probe historical versions.
    authorize LibraryBuild, action_name == "create" ? :create? : :show?
    library = policy_scope(Library).find(params.expect(:library_id))
    @version = library.library_versions.find(params.expect(:library_version_id))
  end

  def build_payload
    storage = LibraryBuilds::Storage.new(@build)
    { id: @build.id, library_version_id: @version.id, version_number: @version.version_number,
      generation: @build.generation, status: @build.status, requested_at: @build.requested_at,
      started_at: @build.started_at, completed_at: @build.completed_at, last_error: @build.last_error,
      published_generation: @build.published_generation, published_at: @build.published_at,
      folder_path: (@build.published? ? storage.folder_path.to_s : nil),
      download_url: (@build.published? ? download_library_library_version_build_path(@version.library_id, @version.id) : nil) }
  end
end
