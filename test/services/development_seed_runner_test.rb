require "test_helper"
require Rails.root.join("db/development_seed_runner").to_s

class DevelopmentSeedRunnerTest < ActiveSupport::TestCase
  test "runs demo data by default in development" do
    output = StringIO.new
    received_output = nil
    demo_seeder = ->(output:) { received_output = output }

    DevelopmentSeedRunner.call(
      mode: "demo",
      environment: "development",
      output:,
      demo_seeder:
    )

    assert_same output, received_output
  end

  test "runs real-world data with the configured archive in development" do
    output = StringIO.new
    archive_path = "/data/real-world.zip"
    received_arguments = nil

    replacement = lambda do |archive_path:, output:|
      received_arguments = { archive_path:, output: }
    end
    DevelopmentSeedRunner.call(
      mode: "real_world",
      archive_path:,
      environment: "development",
      output:,
      real_world_seeder: replacement
    )

    assert_equal archive_path, received_arguments.fetch(:archive_path)
    assert_same output, received_arguments.fetch(:output)
  end

  test "uses the conventional archive path when no override is supplied" do
    received_archive_path = nil

    replacement = lambda do |archive_path:, output:|
      received_archive_path = archive_path
    end
    DevelopmentSeedRunner.call(
      mode: "real_world",
      archive_path: nil,
      environment: "development",
      output: StringIO.new,
      real_world_seeder: replacement
    )

    assert_equal RealWorldDataSeeder::DEFAULT_ARCHIVE_PATH, received_archive_path
  end

  test "skips all destructive seeding outside development" do
    output = StringIO.new
    unexpected_call = ->(**) { flunk "a destructive seeder was called" }

    DevelopmentSeedRunner.call(
      mode: "real_world",
      environment: "test",
      output:,
      demo_seeder: unexpected_call,
      real_world_seeder: unexpected_call
    )

    assert_equal "Skipping destructive seed data outside development.\n", output.string
  end

  test "rejects unknown seed modes" do
    error = assert_raises(ArgumentError) do
      DevelopmentSeedRunner.call(mode: "unknown", environment: "development", output: StringIO.new)
    end

    assert_equal 'Unknown SEED_DATA mode "unknown". Choose one of: demo, real_world', error.message
  end
end
