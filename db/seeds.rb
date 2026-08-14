if Rails.env.development?
  require_relative "demo_data_seeder"

  DemoDataSeeder.call
else
  puts "Skipping destructive demo data outside development."
end
