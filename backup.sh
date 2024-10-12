#!/bin/bash

# Set current date for the backup
BACKUP_DATE=$(date '+%Y-%m-%d')

# Function to detect and use the correct Docker Compose command
function get_docker_compose_command {
    if command -v docker-compose >/dev/null 2>&1; then
        echo "docker-compose"
    else
        echo "docker compose"
    fi
}

DOCKER_COMPOSE=$(get_docker_compose_command)

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

# Check if PostgreSQL and InfluxDB are running
echo "Checking if PostgreSQL and InfluxDB containers are running..."

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

echo "Ok, PostgreSQL and InfluxDB containers are both running."
echo

# PostgreSQL Backup
echo "Creating PostgreSQL backup..."
PG_BACKUP_FILE="solectrus-postgresql-backup-$BACKUP_DATE.sql.gz"
$DOCKER_COMPOSE exec $POSTGRES_SERVICE pg_dumpall -U postgres | gzip >$PG_BACKUP_FILE
if [ $? -eq 0 ]; then
    PG_SIZE=$(du -h "$PG_BACKUP_FILE" | awk '{print $1}')
    echo "PostgreSQL backup saved as $PG_BACKUP_FILE ($PG_SIZE)"
else
    echo "PostgreSQL backup failed."
    exit 1
fi
echo

# InfluxDB Backup
echo "Creating InfluxDB backup..."
INFLUX_BACKUP_PATH=/tmp/solectrus-influxdb-backup-$BACKUP_DATE
INFLUX_TOKEN=$(grep '^INFLUX_ADMIN_TOKEN=' .env | cut -d '=' -f2-)
INFLUX_BACKUP_FILE="solectrus-influxdb-backup-$BACKUP_DATE.tar.gz"
$DOCKER_COMPOSE exec influxdb influx backup $INFLUX_BACKUP_PATH/ -t $INFLUX_TOKEN
$DOCKER_COMPOSE exec influxdb tar -czf $INFLUX_BACKUP_PATH.tar.gz -C /tmp solectrus-influxdb-backup-$BACKUP_DATE
docker cp $($DOCKER_COMPOSE ps -q influxdb):$INFLUX_BACKUP_PATH.tar.gz $INFLUX_BACKUP_FILE
$DOCKER_COMPOSE exec influxdb rm -rf $INFLUX_BACKUP_PATH $INFLUX_BACKUP_PATH.tar.gz
if [ $? -eq 0 ]; then
    INFLUX_SIZE=$(du -h "$INFLUX_BACKUP_FILE" | awk '{print $1}')
    echo "InfluxDB backup saved as $INFLUX_BACKUP_FILE ($INFLUX_SIZE)"
else
    echo "InfluxDB backup failed."
    exit 1
fi
echo

# Combine both backups into a single tar.gz archive
COMBINED_BACKUP_FILE="solectrus-backup-$BACKUP_DATE.tar.gz"
tar -czf $COMBINED_BACKUP_FILE $PG_BACKUP_FILE $INFLUX_BACKUP_FILE
if [ $? -eq 0 ]; then
    COMBINED_SIZE=$(du -h "$COMBINED_BACKUP_FILE" | awk '{print $1}')
    echo "Combined backup saved as $COMBINED_BACKUP_FILE ($COMBINED_SIZE)"
else
    echo "Failed to create combined backup."
    exit 1
fi

# Delete individual backup files
rm $PG_BACKUP_FILE
rm $INFLUX_BACKUP_FILE

echo "Backup process completed."
