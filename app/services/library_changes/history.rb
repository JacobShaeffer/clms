require "set"

module LibraryChanges
  class History
    attr_reader :changes

    def initialize(changes:, hidden_content_ids: [])
      @changes = changes.to_a
      @hidden_content_ids = hidden_content_ids.to_set
      @by_id = @changes.index_by(&:id)
      @dependents = Hash.new { |hash, key| hash[key] = [] }
      @children = Hash.new { |hash, key| hash[key] = [] }
      @changes.each do |change|
        prerequisites = change.dependency_links.map(&:prerequisite_change_id).select { |id| @by_id.key?(id) }
        prerequisites.each { |id| @dependents[id] << change }
        # Show each edit once; its other prerequisites remain available in the details.
        @children[prerequisites.max] << change
      end
    end

    def dependent_changes(change, active_only: false)
      seen = Set.new
      pending = @dependents[change.id].dup
      result = []
      until pending.empty?
        dependent = pending.pop
        next unless seen.add?(dependent.id)

        result << dependent unless active_only && dependent.undone?
        pending.concat(@dependents[dependent.id])
      end
      result.sort_by(&:id)
    end

    def prerequisites(change)
      change.dependency_links.filter_map { |link| @by_id[link.prerequisite_change_id] }
    end

    def visible?(change)
      return true if @hidden_content_ids.empty?

      content_id = change.direct_target&.content_id || change.details["content_id"]
      !@hidden_content_ids.include?(content_id)
    end

    def visible_changes
      changes.select { |change| visible?(change) }
    end

    def visible_targets(change)
      change.library_change_targets.reject { |target| @hidden_content_ids.include?(target.content_id) }
    end

    def rows
      result = []
      pending = @children[nil].reverse.map { |change| [ change, 0 ] }
      until pending.empty?
        change, depth = pending.pop
        visible = visible?(change)
        result << [ change, depth ] if visible
        child_depth = visible ? depth + 1 : depth
        pending.concat(@children[change.id].reverse.map { |child| [ child, child_depth ] })
      end
      result
    end
  end
end
