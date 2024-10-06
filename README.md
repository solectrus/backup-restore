# SOLECTRUS Backup & Restore

This repository contains scripts to backup and restore both PostgreSQL and InfluxDB databases for a SOLECTRUS installation. The following scripts are provided:

## backup.sh

The `backup.sh` script creates backups of both PostgreSQL and InfluxDB databases and combines them into a single compressed file. It is designed specifically for use within a SOLECTRUS setup, ensuring consistent backups of the required services.

How it works:

- A PostgreSQL backup is created using `pg_dumpall` and compressed with `gzip`.
- An InfluxDB backup is created using the `influx backup` command.
- Both backups are combined into a single `tar.gz` file named `solectrus-backup-<DATE>.tar.gz`.

Usage:

```bash
./backup.sh
```

The backup file will be saved in the current directory with the format `solectrus-backup-<DATE>.tar.gz`, where `<DATE>` is the current date.

## restore.sh

The `restore.sh` script restores both PostgreSQL and InfluxDB databases from a previously created backup file. It ensures that only PostgreSQL and InfluxDB containers are running during the restore process to prevent any conflicts.

How it works:

- It checks for the presence of a valid `.env` file and a valid Docker Compose configuration using `docker compose config`.
- It extracts the combined backup file and restores the databases.
- The PostgreSQL database is restored using `psql`, and the InfluxDB database is restored using the `influx restore` command.
- It stops all other containers except PostgreSQL and InfluxDB during the restore process.

Usage:

```bash
./restore.sh <DATE>
```

You need to provide the date of the backup as a parameter, e.g.:

```bash
./restore.sh 2024-10-06
```

The script will then restore the backup from `solectrus-backup-2024-10-06.tar.gz`.

Requirements:

- Valid SOLECTRUS installation (including both PostgreSQL and InfluxDB services)
- Docker Compose configuration file (e.g., `docker-compose.yml` or `compose.yaml`)
- `.env` file with necessary environment variables for InfluxDB

With these scripts, you can easily manage the backup and restore processes for PostgreSQL and InfluxDB databases in your SOLECTRUS setup.

# Download and Installation

To use the scripts, you can download them directly into your SOLECTRUS installation directory:

```bash
# Change to your SOLECTRUS installation directory
cd /path/to/solectrus

# Download backup.sh and restore.sh
curl -o backup.sh https://raw.githubusercontent.com/solectrus/backup-restore/refs/heads/main/backup.sh
curl -o restore.sh https://raw.githubusercontent.com/solectrus/backup-restore/refs/heads/main/restore.sh

# Make both scripts executable
chmod +x backup.sh restore.sh
```
