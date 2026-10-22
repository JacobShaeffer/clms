.\" SolarHub PostgreSQL production setup guide.
.nr PS 10
.nr VS 13
.nr HM 0.75i
.nr FM 0.65i
.nr PO 0.75i
.nr LL 7i
.ds LH SolarHub
.ds RH PostgreSQL Setup
.ds LF Production Server Guide
.ds RF Page %
.
.TL
SolarHub PostgreSQL Production Setup
.AU
Single-server Ubuntu/Debian deployment with Docker and Kamal
.AI
Prepared October 20, 2026
.
.PP
This guide installs PostgreSQL directly on the same server that runs the
SolarHub Docker containers. It creates a restricted PostgreSQL role and four
production databases, then permits database connections only from Kamal's
Docker network.
.
.B "Important security rule"
.PP
Do not expose PostgreSQL port 5432 to the public internet. The database should
listen only on localhost and the private Docker network gateway.
.
.NH 1
Install PostgreSQL
.PP
Run these commands on the server from an administrator account with sudo
access:
.
.DS L
.ft CR
.nf
sudo apt update
sudo apt install -y postgresql postgresql-client
sudo systemctl enable --now postgresql
sudo systemctl status postgresql --no-pager
psql --version
.fi
.ft R
.DE
.PP
The status command should report that PostgreSQL is active. Record the major
version printed by psql; it is used in configuration paths later.
.
.NH 1
Create the Kamal Docker network
.PP
Run this as the deploy user:
.
.DS L
.ft CR
.nf
docker network inspect kamal >/dev/null 2>&1 || docker network create kamal
.fi
.ft R
.DE
.PP
Display the network subnet and host gateway:
.
.DS L
.ft CR
.nf
docker network inspect kamal \
  --format 'Subnet={{(index .IPAM.Config 0).Subnet}} Gateway={{(index .IPAM.Config 0).Gateway}}'
.fi
.ft R
.DE
.PP
Record both values. A typical result looks like this:
.
.DS L
.ft CR
.nf
Subnet=172.18.0.0/16 Gateway=172.18.0.1
.fi
.ft R
.DE
.PP
The rest of this guide calls these values DOCKER_SUBNET and DOCKER_GATEWAY.
Use the actual values reported by your server.
.
.NH 1
Configure PostgreSQL network access
.PP
List the installed PostgreSQL version directory:
.
.DS L
.ft CR
.nf
ls /etc/postgresql
.fi
.ft R
.DE
.PP
Edit the server configuration, replacing VERSION with that directory name:
.
.DS L
.ft CR
.nf
sudoedit /etc/postgresql/VERSION/main/postgresql.conf
.fi
.ft R
.DE
.PP
Set these values, replacing DOCKER_GATEWAY with the network gateway recorded
above:
.
.DS L
.ft CR
.nf
listen_addresses = 'localhost,DOCKER_GATEWAY'
password_encryption = 'scram-sha-256'
.fi
.ft R
.DE
.PP
Example:
.
.DS L
.ft CR
.nf
listen_addresses = 'localhost,172.18.0.1'
password_encryption = 'scram-sha-256'
.fi
.ft R
.DE
.PP
Do not use an asterisk for listen_addresses. Restart PostgreSQL:
.
.DS L
.ft CR
.nf
sudo systemctl restart postgresql
.fi
.ft R
.DE
.
.NH 1
Create the restricted SolarHub role
.PP
Generate a long random password and save it in a password manager. Then create
the PostgreSQL login role:
.
.DS L
.ft CR
.nf
sudo -u postgres createuser --login --pwprompt --no-superuser --no-createdb --no-createrole solarhub
.fi
.ft R
.DE
.PP
Enter the generated password when prompted. This role deliberately cannot
create databases, roles, or superusers.
.
.NH 1
Create the production databases
.PP
Because the SolarHub role does not have CREATEDB permission, create the four
production databases once using the PostgreSQL administrator:
.
.DS L
.ft CR
.nf
sudo -u postgres createdb --owner=solarhub solarhub_production
sudo -u postgres createdb --owner=solarhub solarhub_production_cache
sudo -u postgres createdb --owner=solarhub solarhub_production_queue
sudo -u postgres createdb --owner=solarhub solarhub_production_cable
.fi
.ft R
.DE
.PP
Rails will not need permission to create databases. During deployment,
bin/rails db:prepare will create tables and run migrations inside these existing
databases.
.PP
Verify the role and databases:
.
.DS L
.ft CR
.nf
sudo -u postgres psql -c "\edu solarhub"
sudo -u postgres psql -l
.fi
.ft R
.DE
.PP
The SolarHub role should own all four databases and should not be a superuser.
.
.NH 1
Authorize connections from Docker
.PP
Edit the client-authentication configuration:
.
.DS L
.ft CR
.nf
sudoedit /etc/postgresql/VERSION/main/pg_hba.conf
.fi
.ft R
.DE
.PP
Add these lines at the end of the file. Replace DOCKER_SUBNET with the actual
network subnet:
.
.DS L
.ft CR
.nf
host  solarhub_production        solarhub  DOCKER_SUBNET  scram-sha-256
host  solarhub_production_cache  solarhub  DOCKER_SUBNET  scram-sha-256
host  solarhub_production_queue  solarhub  DOCKER_SUBNET  scram-sha-256
host  solarhub_production_cable  solarhub  DOCKER_SUBNET  scram-sha-256
.fi
.ft R
.DE
.PP
Example:
.
.DS L
.ft CR
.nf
host  solarhub_production        solarhub  172.18.0.0/16  scram-sha-256
host  solarhub_production_cache  solarhub  172.18.0.0/16  scram-sha-256
host  solarhub_production_queue  solarhub  172.18.0.0/16  scram-sha-256
host  solarhub_production_cable  solarhub  172.18.0.0/16  scram-sha-256
.fi
.ft R
.DE
.PP
Check for pg_hba.conf parsing errors:
.
.DS L
.ft CR
.nf
sudo -u postgres psql -c "SELECT line_number, error FROM pg_hba_file_rules WHERE error IS NOT NULL;"
.fi
.ft R
.DE
.PP
The query should return zero rows. Restart PostgreSQL:
.
.DS L
.ft CR
.nf
sudo systemctl restart postgresql
.fi
.ft R
.DE
.PP
Confirm that PostgreSQL listens only on localhost and the Docker gateway:
.
.DS L
.ft CR
.nf
sudo ss -ltnp | grep 5432
.fi
.ft R
.DE
.PP
The output should not contain 0.0.0.0:5432 or the server's public IP address.
.
.NH 1
Configure the firewall
.PP
Check whether UFW is active:
.
.DS L
.ft CR
.nf
sudo ufw status
.fi
.ft R
.DE
.PP
If it is active, allow only the Docker subnet to reach PostgreSQL on the Docker
gateway:
.
.DS L
.ft CR
.nf
sudo ufw allow from DOCKER_SUBNET to DOCKER_GATEWAY port 5432 proto tcp
.fi
.ft R
.DE
.PP
Example:
.
.DS L
.ft CR
.nf
sudo ufw allow from 172.18.0.0/16 to 172.18.0.1 port 5432 proto tcp
.fi
.ft R
.DE
.PP
Do not add a public allow rule for port 5432.
.
.NH 1
Test from a Docker container
.PP
Replace POSTGRES_MAJOR with the PostgreSQL major version and DOCKER_GATEWAY
with the actual gateway. Docker may download the matching client image the first
time this command runs:
.
.DS L
.ft CR
.nf
docker run --rm -it --network kamal postgres:POSTGRES_MAJOR-alpine \
  psql --host=DOCKER_GATEWAY --username=solarhub \
  --dbname=solarhub_production --password \
  --command='select current_database(), current_user;'
.fi
.ft R
.DE
.PP
Enter the SolarHub database password when prompted. Successful output identifies
solarhub_production as the current database and solarhub as the current user.
Do not continue to deployment until this test passes.
.
.NH 1
Configure Kamal
.PP
In config/deploy.yml, add the PostgreSQL settings. Replace DOCKER_GATEWAY with
the actual gateway:
.
.DS L
.ft CR
.nf
env:
  secret:
    - RAILS_MASTER_KEY
    - POSTGRES_PASSWORD

  clear:
    SOLID_QUEUE_IN_PUMA: true
    POSTGRES_HOST: DOCKER_GATEWAY
    POSTGRES_USER: solarhub
    POSTGRES_DB: solarhub_production
    POSTGRES_CACHE_DB: solarhub_production_cache
    POSTGRES_QUEUE_DB: solarhub_production_queue
    POSTGRES_CABLE_DB: solarhub_production_cable
.fi
.ft R
.DE
.PP
In .kamal/secrets, add a reference to the environment variable. Do not put the
actual password in this tracked file:
.
.DS L
.ft CR
.nf
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
.fi
.ft R
.DE
.PP
Inside the development container, load the password without placing it in shell
history:
.
.DS L
.ft CR
.nf
read -rsp "PostgreSQL password: " POSTGRES_PASSWORD
export POSTGRES_PASSWORD
echo
.fi
.ft R
.DE
.PP
Check the resulting deployment configuration:
.
.DS L
.ft CR
.nf
bin/kamal config
.fi
.ft R
.DE
.
.NH 1
Completion checklist
.IP \(bu 3
PostgreSQL is active and enabled at boot.
.IP \(bu 3
The solarhub role is not a superuser and cannot create databases or roles.
.IP \(bu 3
All four production databases exist and are owned by solarhub.
.IP \(bu 3
PostgreSQL listens only on localhost and the Kamal Docker gateway.
.IP \(bu 3
pg_hba.conf permits SCRAM authentication only from the Kamal subnet.
.IP \(bu 3
The Docker-based connection test succeeds.
.IP \(bu 3
The PostgreSQL password is stored in a password manager and is not committed.
.IP \(bu 3
Kamal receives POSTGRES_PASSWORD as a secret.
.
.NH 1
Official references
.PP
Ubuntu PostgreSQL installation and configuration:
.DS L
.ft CR
.nf
https://documentation.ubuntu.com/server/how-to/databases/install-postgresql/
.fi
.ft R
.DE
.PP
PostgreSQL role documentation:
.DS L
.ft CR
.nf
https://www.postgresql.org/docs/current/sql-createrole.html
.fi
.ft R
.DE
.PP
PostgreSQL client authentication documentation:
.DS L
.ft CR
.nf
https://www.postgresql.org/docs/current/auth-pg-hba-conf.html
.fi
.ft R
.DE
.PP
Kamal Docker network documentation:
.DS L
.ft CR
.nf
https://kamal-deploy.org/docs/upgrading/network-changes/
.fi
.ft R
.DE
