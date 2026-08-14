# SolarSPELL Content and Library Management System (CLMS)

This app is build using devcontainers and should be developed using the vscode extention of the same name.

It is setup to use postgres, but more testing will need to be done to ensure the production deploy will be 
handled smoothly. Kamal is installed by default with rails, and it should be used for delpoy. Don't know 
how that works though.


TODO:
1. devise action_mailer needs to be set for production

## Styling

Bootstrap 5.3.8, loaded from jsDelivr, is the application's primary UI toolkit. Use Bootstrap components and utilities first, and add only narrowly scoped custom rules to `app/assets/stylesheets/application.css` when Bootstrap is insufficient. Tailwind is intentionally not installed; do not add Tailwind utility classes to views.

## Development demo data

Run `ruby bin/rails db:seed` to rebuild the development database with demonstration data.

This command is destructive in development. It deletes all application records and Active Storage files before loading the demo dataset. Outside development, the seed command skips the demo dataset and does not delete records.

The seed creates one account for each role. Sign in with `role@role.com` and the password `rolerole`. For example, use `admin@admin.com` with `adminadmin` or `intern_plus@intern_plus.com` with `intern_plusintern_plus`.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...
