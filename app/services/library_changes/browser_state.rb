module LibraryChanges
  class BrowserState
    def initialize(library_version:)
      changes = library_version.library_changes.not_undone
        .includes(:dependents, :library_change_targets)
        .ordered
        .to_a
      @targets = changes.flat_map(&:library_change_targets)
    end

    def direct_changes_for_folder(folder)
      direct_changes("folder", folder.id)
    end

    def direct_changes_for_placement(placement)
      direct_changes("content", placement.id)
    end

    private

    attr_reader :targets

    def direct_changes(target_kind, target_id)
      targets.filter_map do |target|
        next unless target.direct? && target.target_kind == target_kind && target.target_id == target_id

        target.library_change
      end.uniq(&:id).sort_by(&:id)
    end
  end
end
