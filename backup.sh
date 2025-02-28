#!/bin/bash

# Set current date for the backup
BACKUP_DATE=$(date '+%Y-%m-%d')

# Default values
BACKUP_DIR="."
BACKUP_RETENTION_DAYS=""

echo -e "SOLECTRUS Backup Script\n"

# Parse named arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
    --backup-dir)
        BACKUP_DIR="$2"
        shift 2
        ;;
    --retention-days)
        BACKUP_RETENTION_DAYS="$2"
        shift 2
        ;;
    -h | --help)
        echo -e "Usage: $0 [--backup-dir DIR] [--retention-days DAYS]\n"
        echo -e "Creates a backup of SOLECTRUS databases (PostgreSQL and InfluxDB)\n"
        echo -e "Arguments:"
        echo -e "  --backup-dir       Directory where the backup will be stored (default: current directory)."
        echo -e "  --retention-days   Number of days to keep backups. If not specified, backups are kept forever."
        exit 0
        ;;
    *)
        echo "Unknown parameter: $1"
        echo "Use --help to see the usage"
        exit 1
        ;;
    esac
done

# Ensure the target directory exists
mkdir -p "$BACKUP_DIR"

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
$DOCKER_COMPOSE exec $POSTGRES_SERVICE pg_dump -U postgres --clean --if-exists --dbname=solectrus_production | gzip >$PG_BACKUP_FILE
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
COMBINED_BACKUP_FILE="$BACKUP_DIR/solectrus-backup-$BACKUP_DATE.tar.gz"
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

# Delete old backups only if retention days are specified
if [[ -n "$BACKUP_RETENTION_DAYS" ]]; then
    echo "Deleting backups older than $BACKUP_RETENTION_DAYS days..."
    find "$BACKUP_DIR" -maxdepth 1 -name "solectrus-backup-*.tar.gz" -mtime +$BACKUP_RETENTION_DAYS -exec rm {} \;
    echo "Old backups deleted."
else
    echo "No retention period specified. Old backups will not be deleted."
fi
