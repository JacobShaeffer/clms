class LibraryExportJob < ApplicationJob
  queue_as :background

  def self.enqueue(build_id, generation)
    perform_later(build_id, generation)
  rescue StandardError => error
    # The queued record is durable even if the separate queue database is down.
    # RecoverLibraryBuildsJob will retry delivery without rotating the version.
    Rails.logger.error("Could not enqueue library build #{build_id}: #{error.class}: #{error.message}")
    false
  end

  def perform(build_id, generation)
    build = LibraryBuild.find_by(id: build_id)
    LibraryBuilds::Export.call(build:, generation:) if build
  end
end
