if Rails.env.development?
  require_relative "development_seed_runner"

  DevelopmentSeedRunner.call
else
  puts "Skipping destructive seed data outside development."
end
