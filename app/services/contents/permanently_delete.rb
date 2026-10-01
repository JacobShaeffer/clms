module Contents
  class PermanentlyDelete
    CONTENT_ONLY_ACTIONS = %w[
      add_content move_content remove_content duplicate_content
    ].freeze

    def self.call(content:)
      new(content:).call
    end

    def initialize(content:)
      @content = content
    end

    def call
      content.with_lock do
        raise ArgumentError, "Only trashed content can be permanently deleted" unless content.trashed?

        scrub_library_history!
        LibraryFolderContent.where(content_id: content.id).delete_all
        LibraryVersionContent.where(content_id: content.id).delete_all
        content.destroy!
      end
    end

    private

    attr_reader :content

    def scrub_library_history!
      targets = LibraryChangeTarget.where(content_id: content.id).to_a
      return if targets.empty?

      changes_by_id = LibraryChange.where(id: targets.map(&:library_change_id).uniq).index_by(&:id)
      content_change_ids = changes_by_id.values
        .select { |change| CONTENT_ONLY_ACTIONS.include?(change.action_type) }
        .map(&:id)
      mixed_targets = targets.reject { |target| content_change_ids.include?(target.library_change_id) }

      mixed_targets.group_by(&:library_change_id).each do |change_id, change_targets|
        scrub_mixed_change!(changes_by_id.fetch(change_id), change_targets)
      end
      LibraryChangeTarget.where(id: mixed_targets.map(&:id)).delete_all if mixed_targets.any?

      delete_content_changes!(content_change_ids)
    end

    def scrub_mixed_change!(change, targets)
      placement_ids = targets.map(&:target_id)
      details = change.details.deep_dup

      case change.action_type
      when "remove_folder"
        details["placement_ids"] = reject_ids(details["placement_ids"], placement_ids)
        details["content_ids"] = reject_ids(details["content_ids"], [ content.id ])
        details["placement_snapshots"] = Array(details["placement_snapshots"]).reject do |snapshot|
          snapshot["content_id"].to_i == content.id
        end
      when "duplicate_folder"
        details["placement_ids"] = reject_ids(details["placement_ids"], placement_ids)
      end

      change.update_columns(details:) if details != change.details
    end

    def reject_ids(values, removed_ids)
      removed = removed_ids.map(&:to_i).index_with(true)
      Array(values).reject { |value| removed.key?(value.to_i) }
    end

    def delete_content_changes!(change_ids)
      return if change_ids.empty?

      dependency_scope = LibraryChangeDependency.where(library_change_id: change_ids)
        .or(LibraryChangeDependency.where(prerequisite_change_id: change_ids))
      dependency_scope.delete_all
      LibraryChangeTarget.where(library_change_id: change_ids).delete_all
      LibraryChange.where(id: change_ids).delete_all
    end
  end
end
