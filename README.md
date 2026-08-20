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

Use Kamal to deploy to one Linux server on the local network. Run Kamal from a workstation with this repository and SSH access to the server. Kamal builds the Docker image, deploys it, checks `/up`, routes traffic through Kamal Proxy, and keeps the previous version until the new version is ready.

### 1. Prepare the server

The server needs a fixed local IP address or DNS name, SSH access for the deployment user, Docker, PostgreSQL, and a backup location. The deployment user must be able to run Docker. Kamal can install Docker during setup when the SSH user has the required permission.

Allow ports 80 and 443 through the local firewall. Keep PostgreSQL available only to the application server or local network.

### 2. Create the production databases

The production configuration uses separate PostgreSQL databases for the application, cache, queue, and cable services. Create a PostgreSQL role and the four databases:

```sh
sudo -u postgres createuser --pwprompt clms
sudo -u postgres createdb --owner=clms clms_production
sudo -u postgres createdb --owner=clms clms_production_cache
sudo -u postgres createdb --owner=clms clms_production_queue
sudo -u postgres createdb --owner=clms clms_production_cable
```

If PostgreSQL runs on the same server, use the server's local-network address for `POSTGRES_HOST`. Do not use `localhost`; the application runs in a container.

### 3. Configure Kamal

Update `config/deploy.yml` before the first deployment. Replace the placeholder server address and add the PostgreSQL settings. Replace the example values below with local addresses and DNS names:

```yaml
servers:
  web:
    - clms-server.local

proxy:
  host: clms-server.local

env:
  secret:
    - RAILS_MASTER_KEY
    - POSTGRES_PASSWORD
  clear:
    SOLID_QUEUE_IN_PUMA: true
    POSTGRES_HOST: 192.168.1.25
    POSTGRES_USER: clms
    POSTGRES_DB: clms_production
    POSTGRES_CACHE_DB: clms_production_cache
    POSTGRES_QUEUE_DB: clms_production_queue
    POSTGRES_CABLE_DB: clms_production_cable
```

`config/deploy.yml` already mounts the `clms_storage` Docker volume at `/rails/storage`. This keeps uploaded files when Kamal replaces the application container.

For a single local server, keep `registry.server: localhost:5555`. Kamal creates and uses a local Docker registry for that setting. If the build workstation and server cannot use this registry, replace it with a private registry reachable from both systems.

### 4. Configure secrets

The `.kamal/secrets` file already loads `RAILS_MASTER_KEY` from `config/master.key`. Add the database password without putting the password in Git:

```dotenv
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
```

Before deployment, set `POSTGRES_PASSWORD` in the shell that runs Kamal. Do not commit `.kamal/secrets` with a raw password.

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

Open `http://clms-server.local/up` to confirm the health endpoint. Kamal Proxy sends normal traffic to the application on port 80.

### 6. HTTPS and backups

For an internal HTTP-only service, leave the current SSL settings unchanged. For HTTPS, configure a certificate for Kamal Proxy. Let’s Encrypt requires a public DNS name and access to port 443; use a certificate issued by the local organization when the server is not public. Then enable `config.assume_ssl` and `config.force_ssl` in `config/environments/production.rb`, and set the production mailer host to the server DNS name.

Back up the four PostgreSQL databases and the `clms_storage` Docker volume. Test restoring both before relying on the backups.
