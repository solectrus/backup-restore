#!/bin/bash

echo -e "SOLECTRUS Restore Script\n"

# Function to detect and use the correct Docker Compose command
function get_docker_compose_command {
    if command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

DOCKER_COMPOSE=$(get_docker_compose_command)

# Check if the backup file is passed as a parameter
if [ -z "$1" ]; then
    echo "Usage: $0 <BACKUP_FILE>"
    echo "Restore a backup from the specified file"
    exit 1
fi

# Set the backup file
COMBINED_BACKUP_FILE=$1
BACKUP_DATE=$(echo "$COMBINED_BACKUP_FILE" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}')

if [ -z "$BACKUP_DATE" ]; then
    echo "Error: Backup file name does not contain a valid date (YYYY-MM-DD)."
    exit 1
fi

# Check if .env file exists
if [ ! -f ".env" ]; then
    echo "Error: .env file is missing. Please ensure the .env file is present."
    exit 1
fi

# Check if Docker Compose configuration is valid
if ! $DOCKER_COMPOSE config >/dev/null 2>&1; then
    echo "Error: Docker Compose configuration is invalid or missing. Please ensure your Docker Compose configuration is present and valid."
    exit 1
fi

# Check if the combined backup file exists
if [ ! -f "$COMBINED_BACKUP_FILE" ]; then
    echo "Backup file $COMBINED_BACKUP_FILE does not exist."
    exit 1
fi

# Extract the combined tar.gz file to validate the content
echo "Validating backup files in $COMBINED_BACKUP_FILE..."
tar -tzf $COMBINED_BACKUP_FILE | grep "solectrus-postgresql-backup-$BACKUP_DATE.sql.gz" >/dev/null
PG_BACKUP_VALID=$?

tar -tzf $COMBINED_BACKUP_FILE | grep "solectrus-influxdb-backup-$BACKUP_DATE.tar.gz" >/dev/null
INFLUX_BACKUP_VALID=$?

# Check if both PostgreSQL and InfluxDB backups are present
if [ $PG_BACKUP_VALID -ne 0 ]; then
    echo "PostgreSQL backup file is missing in the combined backup."
    exit 1
fi

if [ $INFLUX_BACKUP_VALID -ne 0 ]; then
    echo "InfluxDB backup file is missing in the combined backup."
    exit 1
fi

echo "Ok, backup file contains backups for both PostgreSQL and InfluxDB."
echo

# Check if PostgreSQL, InfluxDB, and Redis are running
echo "Checking if PostgreSQL, InfluxDB, and Redis containers are running..."

# Check for 'postgresql' or 'db' service for PostgreSQL and remember the service name
POSTGRES_SERVICE=$($DOCKER_COMPOSE ps --services --filter "status=running" | grep -E '^(postgresql|db)$')
if [ -z "$POSTGRES_SERVICE" ]; then
    echo "Error: PostgreSQL container is not running (neither as 'postgresql' nor 'db')."
    exit 1
fi

if ! $DOCKER_COMPOSE ps --services --filter "status=running" | grep -q '^influxdb$'; then
    echo "Error: InfluxDB container is not running."
    exit 1
fi

if ! $DOCKER_COMPOSE ps --services --filter "status=running" | grep -q '^redis$'; then
    echo "Error: Redis container is not running."
    exit 1
fi

echo "Ok, PostgreSQL, InfluxDB, and Redis containers are all running."
echo

# Confirmation prompt
echo "WARNING: This will overwrite all existing data in PostgreSQL and InfluxDB!"
read -p "Are you sure you want to continue? Type 'yes' to proceed: " confirmation

if [ "$confirmation" != "yes" ]; then
    echo "Restore process aborted."
    exit 1
fi
echo

# Check all running containers except PostgreSQL, InfluxDB, and Redis
echo "Checking running containers..."
RUNNING_CONTAINERS=$($DOCKER_COMPOSE ps --services --filter "status=running" | grep -vE '^(postgresql|db|influxdb|redis)$')
echo "Stopping all containers except PostgreSQL, InfluxDB, and Redis..."
$DOCKER_COMPOSE stop $(echo "$RUNNING_CONTAINERS")
echo "All other containers stopped."
echo

# Extract the combined tar.gz file
echo "Extracting backup files from $COMBINED_BACKUP_FILE..."
tar -xzf $COMBINED_BACKUP_FILE
echo "Extraction completed."
echo

# PostgreSQL Restore
PG_BACKUP_FILE="solectrus-postgresql-backup-$BACKUP_DATE.sql.gz"
if [ -f "$PG_BACKUP_FILE" ]; then
    echo "Restoring PostgreSQL backup..."

    gunzip -c $PG_BACKUP_FILE | $DOCKER_COMPOSE exec -T $POSTGRES_SERVICE psql -U postgres -d solectrus_production >/dev/null

    if [ $? -eq 0 ]; then
        echo "PostgreSQL restore completed successfully."
    else
        echo "PostgreSQL restore failed."
    fi
else
    echo "PostgreSQL backup file $PG_BACKUP_FILE not found."
fi
echo

# InfluxDB Restore
INFLUX_BACKUP_FILE="solectrus-influxdb-backup-$BACKUP_DATE.tar.gz"
INFLUX_BACKUP_PATH=/tmp/solectrus-influxdb-backup-$BACKUP_DATE
INFLUX_TOKEN=$(grep '^INFLUX_ADMIN_TOKEN=' .env | cut -d '=' -f2-)
BUCKET_NAME=$(grep '^INFLUX_BUCKET=' .env | cut -d '=' -f2-)
ORG_NAME=$(grep '^INFLUX_ORG=' .env | cut -d '=' -f2-)

if [ -f "$INFLUX_BACKUP_FILE" ]; then
    echo "Restoring InfluxDB backup..."

    # Delete existing bucket before restoring
    $DOCKER_COMPOSE exec influxdb influx bucket delete --name $BUCKET_NAME --org $ORG_NAME -t $INFLUX_TOKEN

    # Copy and extract the backup
    docker cp $INFLUX_BACKUP_FILE $($DOCKER_COMPOSE ps -q influxdb):/tmp/
    $DOCKER_COMPOSE exec influxdb tar -xzf /tmp/solectrus-influxdb-backup-$BACKUP_DATE.tar.gz -C /tmp

    # Restore the InfluxDB backup
    $DOCKER_COMPOSE exec influxdb influx restore /tmp/solectrus-influxdb-backup-$BACKUP_DATE/ -t $INFLUX_TOKEN

    # Cleanup after restore
    $DOCKER_COMPOSE exec influxdb rm -rf /tmp/solectrus-influxdb-backup-$BACKUP_DATE /tmp/solectrus-influxdb-backup-$BACKUP_DATE.tar.gz
    echo "InfluxDB restore completed."
else
    echo "InfluxDB backup file $INFLUX_BACKUP_FILE not found."
fi
echo

# Optional: Cleanup extracted files
rm $PG_BACKUP_FILE
rm $INFLUX_BACKUP_FILE

# Redis flush
echo "Flushing Redis..."
$DOCKER_COMPOSE exec redis redis-cli FLUSHALL
if [ $? -eq 0 ]; then
    echo "Redis cache flushed successfully."
else
    echo "Redis flush failed."
    exit 1
fi
echo

# Restart only previously running containers
echo "Restarting previously running containers..."
if [ -n "$RUNNING_CONTAINERS" ]; then
    $DOCKER_COMPOSE start $(echo "$RUNNING_CONTAINERS")
    echo "Previously running containers restarted."
else
    echo "No containers were previously running."
fi

echo "Restore process completed."
