require "fileutils"

module LibraryBuilds
  class Storage
    def initialize(build)
      @build = build
    end

    def root
      Pathname.new(Rails.configuration.x.library_exports_root).join(build.id.to_s)
    end

    def generation_path(generation)
      root.join("generation-#{Integer(generation)}")
    end

    def archive_path
      generation_path(build.published_generation).join("export.zip")
    end

    def folder_path
      generation_path(build.published_generation).join("export")
    end

    def with_lock
      FileUtils.mkdir_p(root, mode: 0o700)
      File.open(root.join(".lock"), File::RDWR | File::CREAT, 0o600) do |file|
        return false unless file.flock(File::LOCK_EX | File::LOCK_NB)

        yield
      ensure
        file.flock(File::LOCK_UN)
      end
    end

    def cleanup
      published = build.reload.published_generation
      root.children.each do |path|
        next unless path.basename.to_s.match?(/\A(?:generation-\d+|stage-[\w-]+)\z/)
        next if published && path == generation_path(published)

        FileUtils.rm_rf(path)
      end
    end

    private

    attr_reader :build
  end
end
