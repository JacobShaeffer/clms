class LibraryEditControlsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library
  before_action :authorize_editor

  rescue_from LibraryChanges::InvalidUndo, ActiveRecord::RecordInvalid,
    ActiveRecord::RecordNotDestroyed, ActiveRecord::RecordNotFound, with: :render_conflict

  def status
    @library.with_lock do
      changes = receipt_changes
      params[:direction] == "redo" ? validate_redo!(changes) : LibraryChanges::UndoBatch.validate!(changes:, user: current_user, library: @library)
      label = changes.first.action_type.humanize
      label += " (#{changes.length} items)" if changes.length > 1
      render json: { available: true, label: }
    end
  end

  def undo
    mutate(:undo)
  end

  def redo
    mutate(:redo)
  end

  private

  def set_library
    @library = policy_scope(Library).find(params.expect(:library_id))
  end

  def authorize_editor
    head :forbidden unless policy(LibraryFolder).manage?
  end

  def receipt_changes
    LibraryChanges::PageReceipt.resolve(receipt: params[:receipt], user: current_user,
      library: @library, page_session: request.headers[LibraryChanges::PageReceipt::SESSION_HEADER])
  end

  def validate_redo!(changes)
    group = LibraryChanges::Redo.group(changes.first)
    unless group.map(&:id).sort == changes.map(&:id).sort && group.all? { |change| change.user_id == current_user.id && change.undone_by_id == current_user.id }
      raise LibraryChanges::InvalidUndo, "Only edits undone by you on this page can be redone here."
    end
    LibraryChanges::Redo.validate!(changes: group, user: current_user, library: @library)
  end

  def mutate(direction)
    @library.with_lock do
      changes = receipt_changes
      context = params.permit(context: [ :folder_id, :tab, :shelf_id ])[:context]&.to_h&.symbolize_keys || {}
      folder = @library.current_version.library_folders.find_by(id: context[:folder_id])
      ancestors = []
      while folder && !ancestors.include?(folder.id)
        ancestors << folder.id
        folder = folder.parent_folder
      end
      if direction == :undo
        LibraryChanges::UndoBatch.call(changes:, user: current_user, library: @library)
      else
        validate_redo!(changes)
        changes = LibraryChanges::Redo.call(change: changes.first, user: current_user, confirmed_change_ids: changes.map(&:id))
      end
      context[:folder_id] = ancestors.find { |id| @library.current_version.library_folders.exists?(id:) }
      context[:tab] = "all" unless LibrariesController::CONTENT_TABS.include?(context[:tab])
      if context[:shelf_id].present? && !current_user.active_shelves.exists?(shelf_id: context[:shelf_id])
        context[:shelf_id] = nil
      end
      receipt = LibraryChanges::PageReceipt.issue(changes:, user: current_user,
        page_session: request.headers[LibraryChanges::PageReceipt::SESSION_HEADER])
      render json: { receipt:, url: library_path(@library, **context.compact), message: direction == :undo ? "Library edit was undone." : "Library edit was redone." }
    end
  end

  def render_conflict(error)
    render json: { available: false, reason: error.message }, status: :conflict
  end
end
