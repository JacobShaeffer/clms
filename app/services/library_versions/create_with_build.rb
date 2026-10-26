module LibraryVersions
  class CreateWithBuild
    Result = Data.define(:locked_version, :new_version, :build)

    def self.call(library:, version_number:, expected_current_version_id:, user:)
      library.with_lock do
        expected_id = Integer(expected_current_version_id.to_s, exception: false)
        unless expected_id && library.current_version_id == expected_id
          raise LibraryBuilds::Error.new("The current library version changed. Refresh and try again.", code: "stale_version")
        end

        new_version = Create.call(library:, version_number:, user:)
        locked_version = new_version.previous_version
        build = LibraryBuilds::Request.call(library_version: locked_version, user:)
        Result.new(locked_version:, new_version:, build:)
      end
    end
  end
end
