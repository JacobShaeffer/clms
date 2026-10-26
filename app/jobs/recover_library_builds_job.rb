class RecoverLibraryBuildsJob < ApplicationJob
  queue_as :background

  def perform
    LibraryBuild.where(status: %w[ queued exporting ]).where(updated_at: ...10.minutes.ago).find_each do |build|
      LibraryExportJob.enqueue(build.id, build.generation)
    end
    LibraryBuild.find_each do |build|
      storage = LibraryBuilds::Storage.new(build)
      storage.with_lock do
        build.working_files.detach
        storage.cleanup
      end
    end
  end
end
