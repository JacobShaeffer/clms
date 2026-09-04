require_relative "demo_data_seeder"
require_relative "real_world_data_seeder"

class DevelopmentSeedRunner
  MODES = %w[demo real_world].freeze

  def self.call(
    mode: ENV.fetch("SEED_DATA", "demo"),
    archive_path: ENV["REAL_WORLD_DOCUMENTS_ZIP"],
    environment: Rails.env,
    output: $stdout,
    demo_seeder: DemoDataSeeder,
    real_world_seeder: RealWorldDataSeeder
  )
    unless environment.to_s == "development"
      output.puts "Skipping destructive seed data outside development."
      return
    end

    case mode
    when "demo"
      demo_seeder.call(output:)
    when "real_world"
      real_world_seeder.call(
        archive_path: archive_path.presence || RealWorldDataSeeder::DEFAULT_ARCHIVE_PATH,
        output:
      )
    else
      raise ArgumentError, "Unknown SEED_DATA mode #{mode.inspect}. Choose one of: #{MODES.join(', ')}"
    end
  end
end
