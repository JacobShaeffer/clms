class LibraryChangesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_library_and_change

  rescue_from LibraryChanges::InvalidResolution, with: :render_invalid_resolution

  def approve
    authorize @change
    safe_folder_id = safe_folder_id_after_resolution(:approve)
    LibraryChanges::Approve.call(change: @change, user: current_user)

    redirect_to library_path(@library, **page_context(folder_id: safe_folder_id)),
      notice: "Library change was approved.",
      status: :see_other
  end

  def undo
    authorize @change
    safe_folder_id = safe_folder_id_after_resolution(:undo)
    LibraryChanges::Undo.call(change: @change, user: current_user)

    redirect_to library_path(@library, **page_context(folder_id: safe_folder_id)),
      notice: "Library change was undone.",
      status: :see_other
  end

  private

  def set_library_and_change
    @library = policy_scope(Library).find(params.expect(:library_id))
    @change = @library.current_version.library_changes.find(params.expect(:id))
  end

  def safe_folder_id_after_resolution(resolution)
    requested_id = scalar_id(params[:folder_id])
    requested_numeric_id = Integer(requested_id, exception: false)
    return requested_id unless requested_numeric_id

    deleted_folder_ids, surviving_parent_id = deleted_folders_and_parent(resolution)
    return requested_id unless deleted_folder_ids.include?(requested_numeric_id)

    surviving_parent_id
  end

  def deleted_folders_and_parent(resolution)
    if resolution == :approve && @change.remove_folder?
      [ Array(@change.details["folder_ids"]).map(&:to_i), @change.details["source_parent_folder_id"] ]
    elsif resolution == :undo && @change.add_folder?
      [ [ @change.details["folder_id"].to_i ], @change.details["parent_folder_id"] ]
    elsif resolution == :undo && @change.duplicate_folder?
      [ Array(@change.details["folder_ids"]).map(&:to_i), @change.details["destination_folder_id"] ]
    else
      [ [], nil ]
    end
  end

  def page_context(folder_id:)
    {
      folder_id:,
      tab: normalized_tab,
      shelf_id: scalar_id(params[:shelf_id])
    }.compact
  end

  def normalized_tab
    value = params[:tab]
    value if value.is_a?(String) && LibrariesController::CONTENT_TABS.include?(value)
  end

  def scalar_id(value)
    return if value.blank?
    return value if value.is_a?(String) || value.is_a?(Integer)

    raise ActiveRecord::RecordNotFound, "Invalid page context"
  end

  def render_invalid_resolution(error)
    redirect_to library_path(@library, **page_context(folder_id: scalar_id(params[:folder_id]))),
      alert: error.message,
      status: :see_other
  end
end
