# SolarSPELL Content and Library Management System

CLMS is a Rails application for managing learning content, metadata, libraries, library assets, folders, and user shelves.

## Requirements

- Ruby 4.0.5
- PostgreSQL

The application uses Bootstrap 5.3.8 and import maps. No JavaScript build step is required.

## Setup

1. Install Ruby dependencies:

   ```sh
   bundle install
   ```

2. Create and migrate the database:

   ```sh
   bin/rails db:prepare
   ```

3. Start the application:

   ```sh
   bin/dev
   ```

The development server runs on `http://localhost:3000` by default.

## Database configuration

Development uses PostgreSQL with these defaults:

- Host: `localhost`
- User: `postgres`
- Database: `clms_development`

Set `POSTGRES_HOST`, `POSTGRES_USER`, `POSTGRES_PASSWORD`, and `POSTGRES_DB` to override them. Use `POSTGRES_TEST_DB` for the test database.

## Demo data

Run the following command to rebuild the development database with demo data:

```sh
bin/rails db:seed
```

This deletes all development records and Active Storage files before loading data. It does not load demo data outside development.

The seed creates one user for each role: `guest`, `organization`, `volunteer`, `intern`, `intern_plus`, and `admin`. Sign in with `role@role.com` and the password `rolerole`; for example, `admin@admin.com` with `adminadmin`.

## Tests

Run all tests with:

```sh
bin/rails test
```

## Local server deployment with Kamal

Use Kamal to deploy to a Linux server on the local network. Run Kamal from a workstation with this repository and SSH access to the server. Kamal builds the Docker image, deploys it, checks `/up`, routes traffic through Kamal Proxy, and keeps the previous version until the new version is ready.

### 1. Prepare the server

The server needs a stable local address, SSH access for the deployment user, Docker, PostgreSQL, and a backup location. The deployment user must be able to run Docker. Kamal can install Docker during setup when the SSH user has the required permission.

Allow ports 80 and 443 through the local firewall. Keep PostgreSQL available only to the application server or local network.

### 2. Prepare the database

Create the production PostgreSQL role and databases required by `config/database.yml`. Give the application role access only to those databases.

Set the database host to an address the application container can reach. Do not use `localhost` unless PostgreSQL runs in the same container.

### 3. Configure Kamal

Update `config/deploy.yml` before the first deployment:

- Replace the example server address with the local server address.
- Set the proxy host to the local DNS name, when one is available.
- Set the PostgreSQL connection values under `env.clear`.
- Add the database password under `env.secret`.
- Keep persistent storage mounted for uploaded files.
- Configure a Docker registry reachable by the build machine and deployment server. The current `localhost:5555` setting lets Kamal use a local registry.

### 4. Configure secrets

Keep `RAILS_MASTER_KEY`, database passwords, and registry credentials outside the repository. The `.kamal/secrets` file can read them from environment variables or a password manager. Do not commit raw secrets.

### 5. Deploy

From the project directory, confirm that the deployment server is reachable by SSH. Then run the first deployment:

```sh
bin/kamal setup
```

This prepares the server, starts Kamal Proxy, and deploys the application. The application entrypoint runs `bin/rails db:prepare` when the web server starts.

After the first deployment, release updates with:

```sh
bin/kamal deploy
```

Check the deployment and application logs with:

```sh
bin/kamal details
bin/kamal logs
```

Open the server's `/up` endpoint to confirm the health check. Kamal Proxy sends normal traffic to the application on port 80.

### 6. HTTPS and backups

For an internal HTTP-only service, leave the current SSL settings unchanged. For HTTPS, configure a certificate for Kamal Proxy. Enable `config.assume_ssl` and `config.force_ssl` in `config/environments/production.rb` when SSL terminates at the proxy.

Back up the PostgreSQL databases and persistent upload storage. Test restoring both before relying on the backups.
