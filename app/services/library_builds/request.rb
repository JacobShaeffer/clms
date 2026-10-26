module LibraryBuilds
  class Request
    def self.call(library_version:, user:)
      library_version.with_lock do
        unless library_version.locked?
          raise Error.new("Create a new version before building this editable version.", code: "version_not_locked")
        end

        build = library_version.library_build || library_version.build_library_build
        return build if build.persisted? && (build.queued? || build.exporting?)

        build.assign_attributes(
          user:, status: "queued", generation: build.persisted? ? build.generation + 1 : 1,
          requested_at: Time.current, started_at: nil, completed_at: nil, last_error: nil
        )
        build.save!
        build_id, generation = build.id, build.generation
        ActiveRecord.after_all_transactions_commit { LibraryExportJob.enqueue(build_id, generation) }
        build
      end
    end
  end
end
