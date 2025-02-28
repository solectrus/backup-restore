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

You can optionally provide a target directory where the backup file should be stored:

```bash
./backup.sh --backup-dir /path/to/backups
```

You can also specify the number of days to keep backups (older backups will be deleted):

```bash
./backup.sh --retention-days 10
```

Without specifying `--retention-days`, older backups will not be deleted.

## restore.sh

The `restore.sh` script restores both PostgreSQL and InfluxDB databases from a previously created backup file. It ensures that only PostgreSQL and InfluxDB containers are running during the restore process to prevent any conflicts.

How it works:

- It checks for the presence of a valid `.env` file and a valid Docker Compose configuration using `docker compose config`.
- It extracts the combined backup file and restores the databases.
- The PostgreSQL database is restored using `psql`, and the InfluxDB database is restored using the `influx restore` command.
- It stops all other containers except PostgreSQL and InfluxDB during the restore process.

Usage:

```bash
./restore.sh <BACKUP_FILE>
```

You need to provide the filename of the backup (containing the date as YYYY-MM-DD) as a parameter, e.g.:

```bash
./restore.sh /path/to/backups/solectrus-backup-2024-10-06.tar.gz
```

Requirements:

- Valid SOLECTRUS installation (including both PostgreSQL and InfluxDB services)
- Docker Compose configuration file (e.g., `docker-compose.yml` or `compose.yaml`)
- `.env` file with necessary environment variables for InfluxDB

With these scripts, you can easily manage the backup and restore processes for PostgreSQL and InfluxDB databases in your SOLECTRUS setup.

## Download and Installation

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

## Automating Backups with CRON

To ensure regular backups, you can set up a cron job to execute the backup script automatically, e.g. daily at a specific time. Here's how you can do it:

1. Open the crontab editor:

   ```bash
   crontab -e
   ```

2. Add the following line to schedule a daily backup at 2:00 AM:

   ```bash
   0 2 * * * cd /path/to/solectrus && ./backup.sh --backup-dir /path/to/backups --retention-days 10
   ```

   **Explanation:**

   - `0 2 * * *` → Runs the backup script daily at 2:00 AM
   - `cd /path/to/solectrus` → Path to the backup script (change to your SOLECTRUS installation directory)
   - `--backup-dir /path/to/backups` → Directory where backups will be stored (change to your desired backup directory)
   - `--retention-days 10` → Optional parameter to specify the number of days to keep backups (deleting older backups)

To verify that the cron job is active, run:

```bash
crontab -l
```
