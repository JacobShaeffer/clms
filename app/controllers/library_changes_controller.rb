class LibraryChangesController < ApplicationController
  before_action :authenticate_user!
  before_action :authorize_history_access
  before_action :set_library
  before_action :set_change, only: %i[ show undo ]

  rescue_from LibraryChanges::InvalidUndo, with: :render_invalid_undo

  def index
    load_history
    @versions = @library.library_versions.order(created_at: :desc, id: :desc)
  end

  def show
    authorize @change
    load_history
    raise ActiveRecord::RecordNotFound unless @history.visible?(@change)

    @dependent_changes = @history.dependent_changes(@change)
    @undo_dependents = @dependent_changes.reject(&:undone?)
    @visible_undo_dependents = @undo_dependents.select { |change| @history.visible?(change) }
    @can_undo = @change.library_version_id == @library.current_version_id &&
      @change.library_version.editable? && !@change.undone? &&
      [ @change, *@undo_dependents ].all? { |change| policy(change).undo? }
    render partial: "library_changes/modal" if turbo_frame_request?
  end

  def undo
    authorize @change
    if params[:cascade] == "1"
      LibraryChanges::CascadeUndo.call(
        change: @change,
        user: current_user,
        confirmed_dependent_ids: params.permit(dependent_change_ids: []).fetch(:dependent_change_ids, [])
      )
    else
      LibraryChanges::Undo.call(change: @change, user: current_user)
    end

    redirect_to library_changes_path(@library),
      notice: "Library change was undone.",
      status: :see_other
  end

  private

  def authorize_history_access
    authorize LibraryChange, :index?
  end

  def set_library
    @library = policy_scope(Library).find(params.expect(:library_id))
  end

  def set_change
    @change = LibraryChange.joins(:library_version)
      .where(library_versions: { library_id: @library.id }).find(params.expect(:id))
  end

  def load_history
    changes = LibraryChange
      .joins(:library_version).where(library_versions: { library_id: @library.id })
      .includes(:user, :undone_by, :library_version, :library_change_targets, :dependency_links)
      .ordered.to_a
    content_ids = changes.flat_map(&:library_change_targets).filter_map(&:content_id).uniq
    hidden_content_ids = Content.trashed.where(id: content_ids).pluck(:id)
    @history = LibraryChanges::History.new(changes:, hidden_content_ids:)
  end

  def render_invalid_undo(error)
    redirect_to library_changes_path(@library),
      alert: error.message,
      status: :see_other
  end
end
