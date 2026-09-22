require "set"

module LibraryChanges
  class BrowserState
    ChangeGroup = Struct.new(:changes, :batches, :dependency_chain, keyword_init: true)
    Batch = Struct.new(:key, :changes, keyword_init: true)
    BADGE_PRIORITY = { "removed" => 3, "moved" => 2, "new" => 1 }.freeze

    attr_reader :pending_changes

    def initialize(library_version:)
      @pending_changes = library_version.library_changes.pending
        .includes(:user, :prerequisites, :dependents, :library_change_targets)
        .ordered
        .to_a
      @targets = pending_changes.flat_map(&:library_change_targets)
    end

    def badge_for_folder(folder)
      removal_badge(folder, "folder") || target_badge("folder", folder.id)
    end

    def badge_for_placement(placement)
      removal_badge(placement, "content") || target_badge("content", placement.id)
    end

    def direct_changes_for_folder(folder)
      direct_changes("folder", folder.id)
    end

    def direct_changes_for_placement(placement)
      direct_changes("content", placement.id)
    end

    def change_groups
      @change_groups ||= build_change_groups
    end

    private

    attr_reader :targets

    def removal_badge(record, target_kind)
      return unless record.pending_removal_change_id

      direct = targets.any? do |target|
        target.library_change_id == record.pending_removal_change_id &&
          target.target_kind == target_kind && target.target_id == record.id && target.direct?
      end
      direct ? "Removed" : "Parent Folder Removed"
    end

    def target_badge(target_kind, target_id)
      effect = targets
        .select do |target|
          target.target_kind == target_kind && target.target_id == target_id &&
            target.details.fetch("display", true)
        end
        .map(&:effect)
        .max_by { |value| BADGE_PRIORITY.fetch(value, 0) }
      effect&.humanize
    end

    def direct_changes(target_kind, target_id)
      targets.filter_map do |target|
        next unless target.direct? && target.target_kind == target_kind && target.target_id == target_id

        target.library_change
      end.uniq(&:id).sort_by(&:id)
    end

    def build_change_groups
      changes_by_id = pending_changes.index_by(&:id)
      links = changes_by_id.keys.index_with { Set.new }

      pending_changes.group_by(&:batch_key).each_value do |batch_changes|
        connect_changes!(links, batch_changes.map(&:id))
      end
      pending_changes.each do |change|
        change.prerequisite_ids.each do |prerequisite_id|
          next unless changes_by_id.key?(prerequisite_id)

          links.fetch(change.id) << prerequisite_id
          links.fetch(prerequisite_id) << change.id
        end
      end

      components(links).map do |ids|
        changes = ids.map { |id| changes_by_id.fetch(id) }.sort_by(&:id)
        batches = changes.group_by(&:batch_key).map do |key, batch_changes|
          Batch.new(key:, changes: batch_changes)
        end
        dependency_chain = changes.any? do |change|
          change.prerequisite_ids.any? { |id| ids.include?(id) }
        end
        ChangeGroup.new(changes:, batches:, dependency_chain:)
      end.sort_by { |group| group.changes.first.id }
    end

    def connect_changes!(links, ids)
      ids.each_cons(2) do |first_id, second_id|
        links.fetch(first_id) << second_id
        links.fetch(second_id) << first_id
      end
    end

    def components(links)
      remaining_ids = links.keys.to_set
      groups = []
      until remaining_ids.empty?
        pending_ids = [ remaining_ids.first ]
        component = Set.new
        until pending_ids.empty?
          id = pending_ids.pop
          next unless remaining_ids.delete?(id)

          component << id
          pending_ids.concat(links.fetch(id).to_a)
        end
        groups << component
      end
      groups
    end
  end
end
