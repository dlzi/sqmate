#!/bin/bash
#
# SQMATE - Universal SQL Server Manager
# A lightweight tool to manage MySQL and MariaDB portable installations for local development.
#
# Copyright (C) 2025, Daniel Zilli. All rights reserved.
#

# Exit on error, undefined vars, and error in pipes.
set -euo pipefail

# --- Default Configuration & Constants ---

SQL_HOST="localhost"
SQL_PORT="3306"
SQL_DIR=""
SQL_ENGINE=""  # mysql or mariadb (auto-detected)
VERSION="1.0.1"
PROFILE="default"
CONFIG_DIR="${SQMATE_CONFIG_DIR:-${HOME}/.config/sqmate}"
CONFIG_FILE="${CONFIG_DIR}/config_${PROFILE}"
PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}.pid"
SERVER_PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}_${SQL_PORT}.server.pid"
LOGFILE="${CONFIG_DIR}/sqmate_${PROFILE}.log"
SOCKET_FILE="/tmp/sqmate_${PROFILE}_${SQL_PORT}.sock"
SQL_BIN=""

declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARNING]=2 [ERROR]=3)
: "${LOG_LEVEL:=INFO}" # Default log level

declare -r COLOR_INFO='\033[0;34m'    # Blue
declare -r COLOR_SUCCESS='\033[0;32m' # Green
declare -r COLOR_WARNING='\033[0;33m' # Yellow
declare -r COLOR_ERROR='\033[0;31m'   # Red
declare -r COLOR_RESET='\033[0m'      # Reset color

mkdir -p "${CONFIG_DIR}" 2> /dev/null || {
    printf "[ERROR] Failed to create configuration directory: %s\n" "${CONFIG_DIR}" >&2
    exit 1
}

# --- Core Functions ---

# Function: logs a message to a file and outputs it to the console.
log_message() {
    # Input parameters
    local level="$1"
    local message="$2"

    # Validate log level
    local current_level_val="${LOG_LEVELS[${level^^}]:-${LOG_LEVELS[ERROR]}}"
    local configured_level_val="${LOG_LEVELS[${LOG_LEVEL^^}]:-${LOG_LEVELS[INFO]}}"
    if [[ "$current_level_val" -lt "$configured_level_val" ]]; then
        return 0
    fi

    # Prepare metadata
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S' 2> /dev/null) || timestamp="UNKNOWN_TIME"
    local pid=$$

    # Format message for console output
    local formatted
    case "${level^^}" in
        INFO) formatted=$(printf "%s[INFO]%s %s" "$COLOR_INFO" "$COLOR_RESET" "$message") ;;
        SUCCESS) formatted=$(printf "%s[SUCCESS]%s %s" "$COLOR_SUCCESS" "$COLOR_RESET" "$message") ;;
        WARNING) formatted=$(printf "%s[WARNING]%s %s" "$COLOR_WARNING" "$COLOR_RESET" "$message") ;;
        ERROR) formatted=$(printf "%s[ERROR]%s %s" "$COLOR_ERROR" "$COLOR_RESET" "$message") ;;
        DEBUG) formatted=$(printf "[DEBUG] %s" "$message") ;;
        *) formatted=$(printf "%s" "$message") ;;
    esac

    # Write to log file
    printf "[%s] [%s] [PID:%d] %s\n" "$timestamp" "${level^^}" "$pid" "$message" >> "$LOGFILE" 2> /dev/null || {
        printf "[%s] [WARNING] [PID:%d] Failed to write to log file: %s\n" "$timestamp" "$pid" "$LOGFILE" >&2
    }

    # Output to console
    local output_stream=1
    [[ "${level^^}" == "ERROR" || "${level^^}" == "WARNING" ]] && output_stream=2
    if [[ -t "$output_stream" ]]; then
        echo -e "$formatted" >&"$output_stream"
    else
        echo -e "$formatted" | sed 's/\x1b\[[0-9;]*m//g' >&"$output_stream"
    fi
}

# Function: manages PID file operations.
manage_pidfile() {
    # Input parameters
    local action="$1"
    local extra_data="${2:-}"

    case "$action" in
        create)
            # Resolve absolute paths
            local abs_sql_dir
            abs_sql_dir=$(realpath -m "$SQL_DIR" 2> /dev/null) || abs_sql_dir="$SQL_DIR"
            local abs_data_dir="${abs_sql_dir}/data"

            # Create PID file with server info
            if ! cat > "$PIDFILE" << EOF; then
SQL_HOST=$SQL_HOST
SQL_PORT=$SQL_PORT
SQL_DIR=$abs_sql_dir
SQL_ENGINE=$SQL_ENGINE
DATA_DIR=$abs_data_dir
SOCKET_FILE=$SOCKET_FILE
PID=$extra_data
PROFILE=$PROFILE
EOF
                log_message "ERROR" "Failed to write PID file: $PIDFILE"
                return 1
            fi

            # Set file permissions
            chmod 600 "$PIDFILE" 2> /dev/null || log_message "WARNING" "Failed to set permissions on PID file: $PIDFILE"
            return 0
            ;;

        read)
            # Check if PID file exists
            if [ ! -e "$PIDFILE" ]; then
                return 1
            fi

            # Read and validate PID file content
            local content
            content=$(cat "$PIDFILE")
            if ! echo "$content" | grep -qE '^(SQL_HOST|SQL_PORT|SQL_DIR|SQL_ENGINE|DATA_DIR|SOCKET_FILE|PID|PROFILE)=' \
                || ! echo "$content" | grep -q '^PID=' \
                || ! echo "$content" | grep -q '^SQL_HOST=' \
                || ! echo "$content" | grep -q '^SQL_PORT='; then
                log_message "ERROR" "PID file has invalid format: $PIDFILE"
                rm -f "$PIDFILE" 2> /dev/null && log_message "INFO" "Removed invalid PID file: $PIDFILE"
                return 1
            fi

            # Output valid content
            echo "$content"
            return 0
            ;;

        get_value)
            # Extract specific value from PID file
            local pid_data
            pid_data=$(manage_pidfile read) || return 1
            echo "$pid_data" | grep "^${extra_data}=" | cut -d'=' -f2
            return 0
            ;;

        check)
            # Read PID file
            local pid_data server_pid
            pid_data=$(manage_pidfile read) || return 1
            server_pid=$(echo "$pid_data" | grep '^PID=' | cut -d'=' -f2)

            # Validate PID
            if [ -z "$server_pid" ] || ! [[ "$server_pid" =~ ^[0-9]+$ ]]; then
                log_message "WARNING" "Invalid PID in $PIDFILE"
                rm -f "$PIDFILE" 2> /dev/null && log_message "INFO" "Removed invalid PID file: $PIDFILE"
                return 1
            fi

            # Check if process exists
            if ! kill -0 "$server_pid" 2> /dev/null; then
                log_message "WARNING" "SQL server process (PID: $server_pid) not found."
                rm -f "$PIDFILE" 2> /dev/null && log_message "INFO" "Removed stale PID file: $PIDFILE"
                return 1
            fi

            # Validate port binding if lsof is available
            if command -v lsof > /dev/null 2>&1; then
                local port
                port=$(echo "$pid_data" | grep '^SQL_PORT=' | cut -d'=' -f2)
                if ! lsof -i :"$port" -sTCP:LISTEN -t 2> /dev/null | grep -q "^$server_pid$"; then
                    log_message "WARNING" "PID $server_pid does not match process on port $port."
                    rm -f "$PIDFILE" 2> /dev/null && log_message "INFO" "Removed invalid PID file: $PIDFILE"
                    return 1
                fi
            fi
            return 0
            ;;

        cleanup)
            # Remove PID file
            cleanup_pid_files "$PROFILE"
            return 0
            ;;
    esac

    # Invalid action
    return 1
}

# Function: display usage information.
usage() {
    cat << EOF

SQMATE - Universal SQL Server Manager

Usage:
    sqmate <command> [options] [<hostname>:<port>]

Commands:
    init        Initialize SQL data directory and set installation path
    start       Start the SQL server (default: localhost:3306)
    stop        Stop the running server
    restart     Restart the server
    status      Show server status
    config      Show current configuration
    connect     Connect to SQL server
    logs        Show recent error logs
    reset-auth  Reset MariaDB/MySQL root authentication (fixes login issues)
    help        Display this help information
    version     Show version information

Options:
    --sql-dir=<path>     Set MySQL/MariaDB installation directory
    --profile=<name>     Use specific configuration profile
    --host=<hostname>    Set SQL hostname (default: localhost)
    --port=<number>      Set SQL port (default: 3306)
    --debug              Enable debug logging (sets LOG_LEVEL=DEBUG)

Examples:
    sqmate init
    sqmate start
    sqmate start --host=0.0.0.0 --port=3307
    sqmate start --profile=mysql8
    sqmate start --profile=mariadb11
    sqmate config --profile=production
    sqmate connect
    sqmate stop

Profile Creation:
    Profiles are created automatically when you use --profile=<name> for the first time.
    Each profile maintains its own configuration, PID file, and can run simultaneously
    on different ports.

    Example workflow:
    sqmate init --profile=mysql8 --sql-dir=/opt/mysql-8.0.39
    sqmate start --profile=mysql8 --port=3306
    sqmate init --profile=mariadb11 --sql-dir=/opt/mariadb-10.11.5
    sqmate start --profile=mariadb11 --port=3307

Supported Databases:
    - MySQL 5.7, 8.0, 8.1+ (auto-detected)
    - MariaDB 10.3, 10.4, 10.5, 10.6, 10.11, 11.x+ (auto-detected)

Environment Variables:
    SQMATE_CONFIG_DIR   Override default config directory (~/.config/sqmate)
    LOG_LEVEL            Set logging verbosity (DEBUG, INFO, WARNING, ERROR)

EOF
}

# Function: display version information.
show_version() {
    echo "SQMATE - Universal SQL Server Manager"
    echo "Version: ${VERSION}"
    echo "Supports: MySQL and MariaDB portable installations"
}

# --- Validation Functions ---

# Function: validates if a file or directory exists.
validate_path() {
    # Input parameters
    local path="$1"
    local type="$2" # "file" or "dir"
    local description="$3"

    # Check for empty path
    [[ -z "$path" ]] && return 0

    # Validate path based on type
    if [[ "$type" == "file" && ! -f "$path" ]]; then
        log_message "ERROR" "$description '$path' not found."
        return 1
    elif [[ "$type" == "dir" && ! -d "$path" ]]; then
        log_message "ERROR" "$description '$path' not found."
        return 1
    fi

    # Path is valid
    return 0
}

# Function: validates hostname format.
validate_hostname() {
    # Input parameter
    local hostname="$1"

    # Validate hostname format
    if [[ "$hostname" =~ ^[a-zA-Z0-9.-]+$ || "$hostname" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ || "$hostname" =~ ^\[[0-9a-fA-F:]+\]$ ]]; then
        return 0
    fi

    # Log error for invalid hostname
    log_message "ERROR" "Invalid hostname: $hostname"
    return 1
}

# Function: validates port number.
validate_port() {
    # Input parameter
    local port="$1"

    # Validate port number
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        log_message "ERROR" "Invalid port number: $port"
        return 1
    fi

    # Port is valid
    return 0
}

# Function: detects SQL engine type (MySQL or MariaDB).
detect_sql_engine() {
    # Input parameter
    local sql_dir="${SQL_DIR}"
    local mysqld_path="${sql_dir}/bin/mysqld"
    local mariadbd_path="${sql_dir}/bin/mariadbd"
    
    log_message "DEBUG" "Detecting SQL engine type in: $sql_dir"

    # Check for MariaDB first (prefer mariadbd over mysqld)
    if [ -f "$mariadbd_path" ]; then
        SQL_ENGINE="mariadb"
        SQL_BIN="$mariadbd_path"
        log_message "DEBUG" "Found mariadbd binary, detected MariaDB engine"
        return 0
    elif [ -f "$mysqld_path" ]; then
        # Try to get version information to distinguish between MySQL and MariaDB
        local version_output
        version_output=$("$mysqld_path" --version 2>/dev/null) || {
            log_message "ERROR" "Failed to get version from mysqld binary"
            return 1
        }

        log_message "DEBUG" "Version output: $version_output"

        # Detect based on version string
        if echo "$version_output" | grep -qi "mariadb"; then
            SQL_ENGINE="mariadb"
            SQL_BIN="$mysqld_path"
            log_message "DEBUG" "Detected MariaDB engine (using mysqld binary)"
        elif echo "$version_output" | grep -qi "mysql"; then
            SQL_ENGINE="mysql"
            SQL_BIN="$mysqld_path"
            log_message "DEBUG" "Detected MySQL engine"
        else
            log_message "WARNING" "Unable to detect SQL engine type, assuming MySQL"
            SQL_ENGINE="mysql"
            SQL_BIN="$mysqld_path"
        fi
    else
        log_message "ERROR" "Neither mysqld nor mariadbd binary found in: $sql_dir/bin/"
        return 1
    fi

    return 0
}

# Function: validates SQL installation.
validate_sql() {
    # Input parameter
    local sql_dir="${SQL_DIR}"
    log_message "DEBUG" "Validating SQL installation: $sql_dir"

    # Check if SQL directory is set
    if [ -z "$sql_dir" ]; then
        log_message "ERROR" "SQL directory not configured. Run 'sqmate init' first."
        return 1
    fi

    # Validate SQL directory exists
    if ! validate_path "$sql_dir" "dir" "SQL directory"; then
        return 1
    fi

    # Detect engine type
    detect_sql_engine || return 1

    # Check if binary is executable
    if [ ! -x "$SQL_BIN" ]; then
        log_message "ERROR" "SQL server binary is not executable: $SQL_BIN"
        return 1
    fi

    # SQL installation is valid
    return 0
}

# Function: checks if a port is available on a host.
check_port_available() {
    # Input parameters
    local host="$1"
    local port="$2"
    log_message "DEBUG" "Checking port $port availability on host $host"

    # Check port using ss (preferred)
    if command -v ss > /dev/null 2>&1; then
        if ss -tuln | grep -qE "($host|0.0.0.0|\[::\]):$port\s"; then
            log_message "ERROR" "Port $host:$port is in use."
            return 1
        fi
    # Fallback to lsof
    elif command -v lsof > /dev/null 2>&1; then
        if lsof -i :"$port" -sTCP:LISTEN > /dev/null 2>&1; then
            log_message "ERROR" "Port $host:$port is in use."
            return 1
        fi
    # No tools available
    else
        log_message "WARNING" "No port checking tool (ss or lsof) available. Cannot verify if port $host:$port is free."
    fi

    # Port is available
    return 0
}

# --- Configuration Management ---

# Function: parses hostname:port from argument.
parse_hostport() {
    # Input parameter
    local hostport_arg="$1"
    log_message "DEBUG" "Parsing hostport: $hostport_arg"

    # Parse input based on format
    if [[ "$hostport_arg" =~ ^([^:]+):([0-9]+)$ ]]; then
        # Format: host:port
        local parsed_host="${BASH_REMATCH[1]}"
        local parsed_port="${BASH_REMATCH[2]}"
        validate_hostname "$parsed_host" || return 1
        validate_port "$parsed_port" || return 1
        SQL_HOST="$parsed_host"
        SQL_PORT="$parsed_port"
    elif [[ "$hostport_arg" =~ ^:([0-9]+)$ ]]; then
        # Format: :port
        local parsed_port="${BASH_REMATCH[1]}"
        validate_port "$parsed_port" || return 1
        SQL_PORT="$parsed_port"
    elif [[ "$hostport_arg" =~ ^([^:]+):?$ ]]; then
        # Format: host: or just host
        local parsed_host="${BASH_REMATCH[1]}"
        validate_hostname "$parsed_host" || return 1
        SQL_HOST="$parsed_host"
    elif [[ "$hostport_arg" =~ ^[0-9]+$ ]]; then
        # Format: just port number
        validate_port "$hostport_arg" || return 1
        SQL_PORT="$hostport_arg"
    else
        # Invalid format
        log_message "WARNING" "Could not parse '$hostport_arg' as host:port. Using defaults: $SQL_HOST:$SQL_PORT"
    fi

    # Update socket file with new profile/port
    SOCKET_FILE="/tmp/sqmate_${PROFILE}_${SQL_PORT}.sock"
    SERVER_PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}_${SQL_PORT}.server.pid"

    # Log result
    log_message "DEBUG" "Parsed host:port as HOST=$SQL_HOST, PORT=$SQL_PORT"

    return 0
}

# Function: parses command line options.
parse_options() {
    # Initialize variables
    local arg params=()

    # Process command line options
    while [ "$#" -gt 0 ]; do
        arg="$1"
        case "$arg" in
            --sql-dir=*)
                SQL_DIR="${arg#*=}"
                validate_path "$SQL_DIR" "dir" "SQL directory" || return 1
                shift
                ;;
            --profile=*)
                PROFILE="${arg#*=}"
                CONFIG_FILE="${CONFIG_DIR}/config_${PROFILE}"
                PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}.pid"
                SERVER_PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}_${SQL_PORT}.server.pid"
                LOGFILE="${CONFIG_DIR}/sqmate_${PROFILE}.log"
                SOCKET_FILE="/tmp/sqmate_${PROFILE}_${SQL_PORT}.sock"
                shift
                ;;
            --host=*)
                SQL_HOST="${arg#*=}"
                validate_hostname "$SQL_HOST" || return 1
                shift
                ;;
            --port=*)
                SQL_PORT="${arg#*=}"
                validate_port "$SQL_PORT" || return 1
                SOCKET_FILE="/tmp/sqmate_${PROFILE}_${SQL_PORT}.sock"
                SERVER_PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}_${SQL_PORT}.server.pid"
                shift
                ;;
            --debug)
                LOG_LEVEL="DEBUG"
                shift
                ;;
            -*)
                log_message "ERROR" "Unknown option: $arg"
                usage
                return 2
                ;;
            *)
                params+=("$arg")
                shift
                ;;
        esac
    done

    # Process positional arguments (hostname:port)
    if [[ "${#params[@]}" -gt 0 ]]; then
        parse_hostport "${params[0]}" || return 1
    fi

    # Options parsed successfully
    return 0
}

# Function: loads configuration from file.
load_config() {
    # Initialize configuration file path
    local config_file="${CONFIG_DIR}/config_${PROFILE:-default}"
    log_message "DEBUG" "Loading configuration from: $config_file"

    # Ensure config directory exists
    mkdir -p "$CONFIG_DIR" 2> /dev/null || {
        log_message "ERROR" "Failed to create config directory: $CONFIG_DIR"
        return 1
    }
    chmod 700 "$CONFIG_DIR" 2> /dev/null || log_message "WARNING" "Failed to set permissions on config directory"

    # Load configuration if file exists
    if [ -f "$config_file" ]; then
        # Set file permissions
        chmod 600 "$config_file" 2> /dev/null || log_message "WARNING" "Failed to set permissions on config file"

        # Validate config file syntax
        if ! bash -n "$config_file" 2> /dev/null; then
            log_message "ERROR" "Invalid syntax in configuration file: $config_file"
            return 1
        fi

        # Source the configuration
        # shellcheck source=/dev/null
        if ! source "$config_file"; then
            log_message "ERROR" "Failed to load configuration from: $config_file"
            return 1
        fi
        log_message "DEBUG" "Loaded configuration from file"
    else
        log_message "DEBUG" "No configuration file found, using defaults."
    fi

    # Update global config file variable
    CONFIG_FILE="$config_file"

    # Update dependent variables
    PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}.pid"
    SERVER_PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}_${SQL_PORT}.server.pid"
    LOGFILE="${CONFIG_DIR}/sqmate_${PROFILE}.log"
    SOCKET_FILE="/tmp/sqmate_${PROFILE}_${SQL_PORT}.sock"

    # Configuration loaded successfully
    return 0
}

# Function: saves current configuration to file.
save_config() {
    # Log save operation
    log_message "DEBUG" "Saving configuration to $CONFIG_FILE"

    # Ensure config directory exists
    mkdir -p "$(dirname "$CONFIG_FILE")" || {
        log_message "ERROR" "Failed to create config directory: $(dirname "$CONFIG_FILE")"
        return 1
    }

    # Resolve absolute paths
    local abs_sql_dir
    abs_sql_dir=$(realpath -m "$SQL_DIR" 2> /dev/null) || abs_sql_dir="$SQL_DIR"

    # Write configuration to file
    if ! cat > "$CONFIG_FILE" << EOF; then
# SQMATE Configuration for profile: $PROFILE
SQL_HOST="$SQL_HOST"
SQL_PORT="$SQL_PORT"
SQL_DIR="$abs_sql_dir"
SQL_ENGINE="$SQL_ENGINE"
SOCKET_FILE="$SOCKET_FILE"
EOF
        log_message "ERROR" "Failed to save configuration to $CONFIG_FILE."
        return 1
    fi

    # Set file permissions
    chmod 600 "$CONFIG_FILE" || log_message "WARNING" "Failed to set permissions on config file"

    # Log success
    log_message "DEBUG" "Configuration saved successfully"

    # Configuration saved successfully
    return 0
}

# Function: show current configuration.
show_config() {
    local engine_display="${SQL_ENGINE:-Not detected}"
    if [ -n "$SQL_ENGINE" ]; then
        engine_display="${SQL_ENGINE^}"  # Capitalize first letter
    fi

    printf "Current Configuration (%s):\n" "$PROFILE"
    printf "  %-15s %s\n" "Profile:" "$PROFILE"
    printf "  %-15s %s\n" "Engine:" "$engine_display"
    printf "  %-15s %s\n" "SQL Host:" "$SQL_HOST"
    printf "  %-15s %s\n" "SQL Port:" "$SQL_PORT"
    printf "  %-15s %s\n" "SQL Directory:" "${SQL_DIR:-Not configured}"
    printf "  %-15s %s\n" "Data Directory:" "${SQL_DIR:+${SQL_DIR}/data}"
    printf "  %-15s %s\n" "Socket File:" "$SOCKET_FILE"
    printf "  %-15s %s\n" "Log Level:" "$LOG_LEVEL"
    printf "  %-15s %s\n" "Config File:" "$CONFIG_FILE"
    printf "  %-15s %s\n" "Log File:" "$LOGFILE"
}

# --- Server Management ---

# Function: Clean up all PID-related files for current profile
cleanup_pid_files() {
    local profile="${1:-$PROFILE}"
    
    log_message "DEBUG" "Cleaning up all files for profile: $profile"
    
    # Remove SQMATE tracking PID
    rm -f "${CONFIG_DIR}/sqmate_${profile}.pid" 2>/dev/null
    
    # Remove server PID files (with port patterns)
    rm -f "${CONFIG_DIR}/sqmate_${profile}_"*.server.pid 2>/dev/null
    
    # Remove socket file(s) for this profile
    rm -f "/tmp/sqmate_${profile}_"*.sock 2>/dev/null
    
    # Could also clean up stale entries from other profiles if needed
}

# Function: finds processes listening on a specified port.
find_port_processes() {
    # Input parameter
    local port="$1"
    local pids=()

    # Check for available tools and find PIDs
    if command -v lsof > /dev/null 2>&1; then
        mapfile -t pids < <(lsof -i :"$port" -sTCP:LISTEN -t 2> /dev/null)
    elif command -v ss > /dev/null 2>&1; then
        mapfile -t pids < <(ss -tuln | grep -w "$port" | awk '{print $NF}' | grep -o '[0-9]\+' | sort -u)
    fi

    # Output found PIDs
    echo "${pids[@]}"
}

# Function: prompts user for SQL directory.
prompt_sql_directory() {
    local current_dir="${SQL_DIR:-}"
    
    if [ -n "$current_dir" ]; then
        log_message "WARNING" "Current SQL directory: $current_dir"
        echo "SQL directory has changed or is invalid."
        echo "Current configured directory: $current_dir"
        echo
    fi
    
    echo "Please enter the path to your MySQL/MariaDB installation directory:"
    echo "(This should contain the 'bin' subdirectory with mysqld or mariadbd)"
    echo
    read -r sql_dir_input
    
    # Sanitize input
    sql_dir_input=$(echo "$sql_dir_input" | tr -d '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    
    if [ -z "$sql_dir_input" ]; then
        log_message "ERROR" "SQL directory cannot be empty"
        return 1
    fi
    
    # Expand tilde
    if [[ "$sql_dir_input" =~ ^~ ]]; then
        sql_dir_input="${sql_dir_input/#\~/$HOME}"
    fi
    
    # Validate directory
    if ! validate_path "$sql_dir_input" "dir" "SQL directory"; then
        return 1
    fi
    
    # Check for MariaDB binary first
    if ! validate_path "${sql_dir_input}/bin/mariadbd" "file" "MariaDB server binary" 2>/dev/null && \
       ! validate_path "${sql_dir_input}/bin/mysqld" "file" "SQL server binary"; then
        log_message "ERROR" "Directory '$sql_dir_input' does not appear to be a valid MySQL/MariaDB installation"
        log_message "ERROR" "Expected to find either: ${sql_dir_input}/bin/mariadbd or ${sql_dir_input}/bin/mysqld"
        return 1
    fi
    
    SQL_DIR="$sql_dir_input"
    return 0
}

# Function: initializes SQL data directory based on engine type.
initialize_data_directory() {
    local data_dir="${SQL_DIR}/data"
    local base_dir="$SQL_DIR"
    
    log_message "INFO" "Initializing ${SQL_ENGINE^} data directory at: $data_dir"
    
    if [ "$SQL_ENGINE" = "mariadb" ]; then
        # MariaDB initialization - try mysql_install_db first, fallback to mysqld --initialize
        local install_db_path="${SQL_DIR}/scripts/mysql_install_db"
        
        if [ -f "$install_db_path" ] && [ -x "$install_db_path" ]; then
            log_message "INFO" "Using MariaDB mysql_install_db script"
            if ! "$install_db_path" --datadir="$data_dir" --basedir="$base_dir" --user="$(whoami)"; then
                log_message "WARNING" "mysql_install_db failed, trying mysqld --initialize"
                if ! "$SQL_BIN" --initialize-insecure --datadir="$data_dir" --basedir="$base_dir"; then
                    log_message "ERROR" "Failed to initialize MariaDB data directory"
                    return 1
                fi
            fi
        else
            log_message "INFO" "Using mysqld --initialize for MariaDB"
            if ! "$SQL_BIN" --initialize-insecure --datadir="$data_dir" --basedir="$base_dir"; then
                log_message "ERROR" "Failed to initialize MariaDB data directory"
                return 1
            fi
        fi
        
        log_message "SUCCESS" "MariaDB data directory initialized (no root password set)"
        log_message "INFO" "You can set a root password after connecting with:"
        log_message "INFO" "  SET PASSWORD FOR 'root'@'localhost' = PASSWORD('your_password');"
        
    else
        # MySQL initialization
        log_message "INFO" "Using mysqld --initialize for MySQL"
        if ! "$SQL_BIN" --initialize --datadir="$data_dir" --basedir="$base_dir"; then
            log_message "ERROR" "Failed to initialize MySQL data directory"
            return 1
        fi
        
        log_message "SUCCESS" "MySQL data directory initialized successfully"
        log_message "WARNING" "Please check ${SQL_DIR}/logs/mysqld_error.log for the temporary root password"
        log_message "INFO" "Change the root password after first connection using:"
        log_message "INFO" "  ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';"
    fi
    
    return 0
}

# Function: initializes SQL data directory and configuration.
init_sql() {
    log_message "INFO" "Initializing SQL configuration for profile: $PROFILE"
    
    # Prompt for SQL directory if not set or invalid
    if [ -z "$SQL_DIR" ] || ! validate_sql 2>/dev/null; then
        if ! prompt_sql_directory; then
            return 1
        fi
    fi
    
    # Validate SQL installation and detect engine
    validate_sql || return 1
    
    # Display detected engine
    log_message "SUCCESS" "Detected ${SQL_ENGINE^} installation"
    
    # Create data directory
    local data_dir="${SQL_DIR}/data"
    local logs_dir="${SQL_DIR}/logs"
    
    mkdir -p "$data_dir" "$logs_dir" || {
        log_message "ERROR" "Failed to create data/logs directories"
        return 1
    }
    
    # Check if already initialized
    if [ -d "$data_dir/mysql" ]; then
        log_message "WARNING" "SQL data directory already initialized at: $data_dir"
    else
        # Initialize based on detected engine
        initialize_data_directory || return 1
    fi
    
    # Save configuration
    save_config || return 1
    log_message "SUCCESS" "Configuration saved to: $CONFIG_FILE"
    
    # Show current configuration
    echo
    show_config
    
    return 0
}

# Function: starts the SQL server.
start_server() {
    # Validate SQL installation
    validate_sql || return 1

    # Check port availability
    check_port_available "$SQL_HOST" "$SQL_PORT" || return 1

    # Set up paths
    local data_dir="${SQL_DIR}/data"
    local logs_dir="${SQL_DIR}/logs"
    local error_log="${logs_dir}/mysqld_error.log"
    local general_log="${logs_dir}/mysqld_general.log"

    # Validate data directory
    validate_path "$data_dir" "dir" "SQL data directory" || {
        log_message "ERROR" "SQL data directory not found. Run 'sqmate init' first."
        return 1
    }

    # Check if data directory is initialized
    if [ ! -d "$data_dir/mysql" ]; then
        log_message "ERROR" "SQL data directory not initialized. Run 'sqmate init' first."
        return 1
    fi

    # Create logs directory
    mkdir -p "$logs_dir" || {
        log_message "ERROR" "Failed to create logs directory: $logs_dir"
        return 1
    }

    # Check for existing server
    if manage_pidfile check; then
        log_message "WARNING" "${SQL_ENGINE^} server is already running. Use 'sqmate restart' or stop it first."
        return 1
    fi

    # Build server command - check if --daemonize is supported
    local daemon_option=""
    if "$SQL_BIN" --help --verbose 2>/dev/null | grep -q -- "--daemonize"; then
        daemon_option="--daemonize"
        log_message "DEBUG" "Using --daemonize option"
    else
        log_message "DEBUG" "MariaDB version does not support --daemonize, starting in background mode"
    fi
    
    local start_command="\"$SQL_BIN\" --datadir=\"$data_dir\" --basedir=\"$SQL_DIR\" --socket=\"$SOCKET_FILE\" --port=\"$SQL_PORT\" --bind-address=\"$SQL_HOST\" --pid-file=\"$SERVER_PIDFILE\" --log-error=\"$error_log\" --general-log --general-log-file=\"$general_log\" $daemon_option"

    # Log server start details
    log_message "INFO" "Starting ${SQL_ENGINE^} server at $SQL_HOST:$SQL_PORT"
    log_message "INFO" "  Data directory: $data_dir"
    log_message "INFO" "  Socket file: $SOCKET_FILE"
    log_message "INFO" "  Error log: $error_log"
    [[ "$PROFILE" != "default" ]] && log_message "INFO" "  Profile: $PROFILE"

    # Start server - always run in background to free the console
    log_message "DEBUG" "Starting server with command: $start_command"
    if [ -n "$daemon_option" ]; then
        # Use daemonize option if available
        eval "$start_command" || {
            log_message "ERROR" "Failed to start ${SQL_ENGINE^} server. Check error log: $error_log"
            return 1
        }
    else
        # Start in background for older MariaDB versions or when daemonize not available
        eval "$start_command" > /dev/null 2>&1 &
        local bg_pid=$!
        # Give it a moment to start
        sleep 1
        # Check if the background process is still running (didn't immediately fail)
        if ! kill -0 "$bg_pid" 2>/dev/null; then
            log_message "ERROR" "Failed to start ${SQL_ENGINE^} server. Check error log: $error_log"
            return 1
        fi
    fi

    # Wait for SQL PID file to be created
    local attempt=0 max_attempts=10
    local sql_pid=""
    while [ "$attempt" -lt "$max_attempts" ]; do
        if [ -f "$SERVER_PIDFILE" ]; then
            sql_pid=$(cat "$SERVER_PIDFILE" 2>/dev/null)
            if [ -n "$sql_pid" ] && kill -0 "$sql_pid" 2>/dev/null; then
                break
            fi
        fi
        sleep 1
        attempt=$((attempt + 1))
    done

    if [ -z "$sql_pid" ] || ! kill -0 "$sql_pid" 2>/dev/null; then
        log_message "ERROR" "${SQL_ENGINE^} server failed to start properly. Check error log: $error_log"
        # Clean up the server PID file if it exists
        rm -f "$SERVER_PIDFILE" 2>/dev/null
        return 1
    fi

    # Create our PID file
    if ! manage_pidfile create "$sql_pid"; then
        log_message "ERROR" "Failed to create PID file"
        kill "$sql_pid" 2> /dev/null
        return 1
    fi

    # Verify server is listening on port
    local attempt=0 max_attempts=10
    local port_bound=0
    while [ "$attempt" -lt "$max_attempts" ]; do
        if command -v lsof > /dev/null 2>&1; then
            if lsof -i :"$SQL_PORT" -sTCP:LISTEN -t 2> /dev/null | grep -q "^$sql_pid$"; then
                port_bound=1
                break
            fi
        elif command -v ss > /dev/null 2>&1; then
            if ss -tuln | grep -qE "($SQL_HOST|0.0.0.0|\[::\]):$SQL_PORT\s"; then
                port_bound=1
                break
            fi
        fi
        sleep 1
        attempt=$((attempt + 1))
    done

    if [ "$port_bound" -eq 0 ]; then
        log_message "ERROR" "${SQL_ENGINE^} server failed to bind to port $SQL_PORT. Check error log: $error_log"
        kill "$sql_pid" 2> /dev/null
        manage_pidfile cleanup
        return 1
    fi

    # Log success
    log_message "SUCCESS" "${SQL_ENGINE^} server started successfully with PID: $sql_pid"

    # Server started successfully
    return 0
}

# Function: stops the SQL server
stop_server() {
    # Initialize variables
    local server_pid sql_host sql_port sql_engine
    local found_server=0

    # Attempt to retrieve server info from PID file
    if manage_pidfile check; then
        server_pid=$(manage_pidfile get_value "PID")
        sql_host=$(manage_pidfile get_value "SQL_HOST")
        sql_port=$(manage_pidfile get_value "SQL_PORT")
        sql_engine=$(manage_pidfile get_value "SQL_ENGINE")
        found_server=1
    else
        # Fallback to checking port directly
        sql_host="$SQL_HOST"
        sql_port="$SQL_PORT"
        sql_engine="${SQL_ENGINE:-SQL}"
        local port_pids
        port_pids=$(find_port_processes "$sql_port")
        if [ -n "$port_pids" ]; then
            server_pid="$port_pids"
            found_server=1
        fi
    fi

    # Handle case where no server is found
    if [ "$found_server" -eq 0 ]; then
        log_message "INFO" "No running SQL server found"
        manage_pidfile cleanup

        return 0
    fi

    # Stop the server process
    local failed=0
    if ! kill -0 "$server_pid" 2> /dev/null; then
        log_message "WARNING" "Process $server_pid not found or already terminated"
    else
        log_message "INFO" "Stopping ${sql_engine^} server process $server_pid on $sql_host:$sql_port"

        # Send SIGTERM for graceful shutdown
        kill -TERM "$server_pid" 2> /dev/null || log_message "WARNING" "Failed to send SIGTERM to $server_pid"
        
        # Wait for graceful shutdown (up to 30 seconds)
        local attempt=0 max_attempts=30
        while [ "$attempt" -lt "$max_attempts" ] && kill -0 "$server_pid" 2> /dev/null; do
            sleep 1
            attempt=$((attempt + 1))
        done

        # Use SIGKILL if necessary
        if kill -0 "$server_pid" 2> /dev/null; then
            log_message "WARNING" "Process $server_pid did not terminate gracefully. Sending SIGKILL..."
            kill -9 "$server_pid" 2> /dev/null
            sleep 2
            if kill -0 "$server_pid" 2> /dev/null; then
                log_message "ERROR" "Failed to terminate process $server_pid"
                failed=1
            fi
        fi
    fi

    # Verify port is free
    if command -v lsof > /dev/null 2>&1 && lsof -i :"$sql_port" -sTCP:LISTEN > /dev/null 2>&1; then
        log_message "ERROR" "Port $sql_host:$sql_port is still in use"
        failed=1
    fi

    # Clean up all PID-related files
    cleanup_pid_files "$PROFILE"

    # Report result
    if [ "$failed" -eq 0 ]; then
        log_message "SUCCESS" "${sql_engine^} server stopped successfully"
        return 0
    else
        log_message "ERROR" "Failed to stop ${sql_engine^} server completely"
        return 1
    fi
}

# Function: checks the status of the SQL server
check_status() {
    # Check if server is running
    if ! manage_pidfile check; then
        log_message "INFO" "No SQL server running"
        return 1
    fi

    # Retrieve server information
    local server_pid sql_host sql_port sql_dir sql_engine data_dir socket_file profile
    server_pid=$(manage_pidfile get_value "PID")
    sql_host=$(manage_pidfile get_value "SQL_HOST")
    sql_port=$(manage_pidfile get_value "SQL_PORT")
    sql_dir=$(manage_pidfile get_value "SQL_DIR")
    sql_engine=$(manage_pidfile get_value "SQL_ENGINE")
    data_dir=$(manage_pidfile get_value "DATA_DIR")
    socket_file=$(manage_pidfile get_value "SOCKET_FILE")
    profile=$(manage_pidfile get_value "PROFILE")

    # Display server status
    log_message "INFO" "${sql_engine^} server is running"
    printf "Server Status:\n"
    printf "  %-15s %s\n" "Status:" "Running"
    printf "  %-15s %s\n" "Engine:" "${sql_engine^}"
    printf "  %-15s %s\n" "Profile:" "${profile:-default}"
    printf "  %-15s %s\n" "PID:" "$server_pid"
    printf "  %-15s %s\n" "URL:" "${sql_engine}://$sql_host:$sql_port/"
    printf "  %-15s %s\n" "SQL Directory:" "$sql_dir"
    printf "  %-15s %s\n" "Data Directory:" "$data_dir"
    printf "  %-15s %s\n" "Socket File:" "$socket_file"
    printf "  %-15s %s\n" "Log file:" "$LOGFILE"

    # Show process start time if available
    if command -v ps > /dev/null 2>&1; then
        local start_time
        start_time=$(ps -o lstart= -p "$server_pid" 2> /dev/null)
        [ -n "$start_time" ] && printf "  %-15s %s\n" "Started:" "$start_time"
    fi

    # Server is running
    return 0
}

# Function: restarts the SQL server
restart_server() {
    # Log restart operation
    log_message "INFO" "Restarting SQL server..."
    
    # Save current server configuration from PID file before stopping
    local saved_host saved_port saved_sql_dir saved_engine saved_profile
    local config_restored=false
    
    if manage_pidfile check; then
        saved_host=$(manage_pidfile get_value "SQL_HOST")
        saved_port=$(manage_pidfile get_value "SQL_PORT")
        saved_sql_dir=$(manage_pidfile get_value "SQL_DIR")
        saved_engine=$(manage_pidfile get_value "SQL_ENGINE")
        saved_profile=$(manage_pidfile get_value "PROFILE")
        
        # Update current configuration with saved values
        [[ -n "$saved_host" ]] && SQL_HOST="$saved_host"
        [[ -n "$saved_port" ]] && SQL_PORT="$saved_port"
        [[ -n "$saved_sql_dir" ]] && SQL_DIR="$saved_sql_dir"
        [[ -n "$saved_engine" ]] && SQL_ENGINE="$saved_engine"
        [[ -n "$saved_profile" ]] && PROFILE="$saved_profile"
        
        config_restored=true
        
        # Log restored configuration details
        log_message "INFO" "Restoring previous configuration:"
        log_message "INFO" "  Engine: ${SQL_ENGINE^}"
        log_message "INFO" "  SQL directory: $SQL_DIR"
        log_message "INFO" "  Host:Port: $SQL_HOST:$SQL_PORT"
        [[ "$PROFILE" != "default" ]] && log_message "INFO" "  Profile: $PROFILE"
        
        log_message "DEBUG" "Full restored config - Engine: $SQL_ENGINE, Host: $SQL_HOST, Port: $SQL_PORT, SQL_Dir: $SQL_DIR, Profile: $PROFILE"
    else
        log_message "WARNING" "No previous server configuration found, using current settings"
    fi
    
    # Stop existing server
    stop_server
    
    # Wait until port is free (up to 10 seconds)
    local attempt=0 max_attempts=10
    while [ "$attempt" -lt "$max_attempts" ]; do
        if check_port_available "$SQL_HOST" "$SQL_PORT"; then
            break
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    
    if [ "$attempt" -eq "$max_attempts" ]; then
        log_message "ERROR" "Port $SQL_HOST:$SQL_PORT still in use after waiting. Cannot restart server."
        return 1
    fi
    
    # Start new server with restored configuration
    start_server || return 1
    
    # Log success
    log_message "SUCCESS" "SQL server restarted successfully"
    
    # Server restarted successfully
    return 0
}

# Function: connects to SQL server
connect_sql() {
    # Check if server is running
    if ! manage_pidfile check; then
        log_message "ERROR" "SQL server is not running. Start it first with: sqmate start"
        return 1
    fi

    # Get connection details
    local socket_file sql_engine
    socket_file=$(manage_pidfile get_value "SOCKET_FILE")
    sql_engine=$(manage_pidfile get_value "SQL_ENGINE")
    
    # Find SQL client - prefer mariadb over mysql for MariaDB installations
    local sql_client=""
    if [ "$sql_engine" = "mariadb" ]; then
        # For MariaDB, prefer mariadb client over mysql client
        if [ -f "${SQL_DIR}/bin/mariadb" ]; then
            sql_client="${SQL_DIR}/bin/mariadb"
            log_message "DEBUG" "Using mariadb client"
        elif [ -f "${SQL_DIR}/bin/mysql" ]; then
            sql_client="${SQL_DIR}/bin/mysql"
            log_message "DEBUG" "Using mysql client (mariadb client not found)"
        fi
    else
        # For MySQL, use mysql client
        sql_client="${SQL_DIR}/bin/mysql"
        log_message "DEBUG" "Using mysql client"
    fi
    
    if [ -z "$sql_client" ] || ! validate_path "$sql_client" "file" "SQL client"; then
        log_message "ERROR" "SQL client not found. Expected: ${SQL_DIR}/bin/mariadb or ${SQL_DIR}/bin/mysql"
        return 1
    fi

    log_message "INFO" "Connecting to ${sql_engine^} server..."
    
    # For MariaDB with authentication issues, try multiple approaches
    if [ "$sql_engine" = "mariadb" ]; then
        log_message "INFO" "Attempting connection without password (MariaDB default)..."
        
        # Try connection without password first
        if "$sql_client" -u root --socket="$socket_file" -e "SELECT 1;" >/dev/null 2>&1; then
            log_message "SUCCESS" "Connected without password. Starting interactive session..."
            "$sql_client" -u root --socket="$socket_file"
        else
            log_message "INFO" "No-password connection failed. Trying system user authentication..."
            
            # Try with current system user (unix_socket plugin)
            local current_user
            current_user=$(whoami)
            if "$sql_client" -u "$current_user" --socket="$socket_file" -e "SELECT 1;" >/dev/null 2>&1; then
                log_message "SUCCESS" "Connected as system user '$current_user'. Starting interactive session..."
                log_message "INFO" "Note: You're connected as '$current_user', not 'root'"
                "$sql_client" -u "$current_user" --socket="$socket_file"
            else
                log_message "INFO" "System user authentication failed. Trying with password..."
                log_message "INFO" "Please enter the root password (press Enter if no password):"
                "$sql_client" -u root -p --socket="$socket_file"
            fi
        fi
    else
        # For MySQL, always prompt for password
        log_message "INFO" "Please enter the root password:"
        "$sql_client" -u root -p --socket="$socket_file"
    fi
    
    local connection_result=$?

    # If all connection attempts failed, provide troubleshooting info
    if [ $connection_result -ne 0 ]; then
        echo ""
        log_message "ERROR" "Connection failed. Here are some troubleshooting options:"
        echo ""
        echo "1. Reset MariaDB root authentication:"
        echo "   sqmate stop"
        echo "   sqmate reset-auth"
        echo ""
        echo "2. Manual reset (advanced):"
        echo "   # Stop server and start in safe mode"
        echo "   sqmate stop"
        echo "   $SQL_BIN --skip-grant-tables --socket=/tmp/sqmate_temp_\$\$.sock \\"
        echo "     --datadir=\"${SQL_DIR}/data\" &"
        echo ""
        echo "   # Connect and fix authentication"
        echo "   $sql_client -u root --socket=/tmp/sqmate_temp_\$\$.sock"
        echo "   # In MariaDB, run:"
        echo "   #   FLUSH PRIVILEGES;"
        echo "   #   ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('');"
        echo "   #   EXIT;"
        echo ""
        echo "   # Kill safe mode and restart normally"
        echo "   pkill $(basename "$SQL_BIN")"
        echo "   sqmate start"
        echo ""
        echo "3. Check if you need to run as a different user:"
        echo "   Current system user: $(whoami)"
        echo "   Try: $sql_client -u $(whoami) --socket=\"$socket_file\""
    fi
}

# Function: resets MariaDB/MySQL authentication
reset_auth() {
    # Validate SQL installation
    validate_sql || return 1
    
    local sql_engine="$SQL_ENGINE"
    local data_dir="${SQL_DIR}/data"
    
    log_message "INFO" "Resetting ${sql_engine^} authentication..."
    
    # Check if server is running and stop it
    if manage_pidfile check; then
        log_message "INFO" "Stopping running server..."
        stop_server || {
            log_message "ERROR" "Failed to stop running server"
            return 1
        }
    fi
    
    # Wait a moment for cleanup
    sleep 2
    
    # Start server in safe mode
    local temp_socket="/tmp/sqmate_reset_$.sock"
    local temp_pid="/tmp/sqmate_reset_$.pid"
    
    log_message "INFO" "Starting server in safe mode (skip authentication)..."
    "$SQL_BIN" --skip-grant-tables --skip-networking \
        --socket="$temp_socket" \
        --pid-file="$temp_pid" \
        --datadir="$data_dir" \
        --basedir="$SQL_DIR" &
    
    local safe_pid=$!
    
    # Wait for server to start
    local attempt=0 max_attempts=10
    while [ "$attempt" -lt "$max_attempts" ]; do
        if [ -S "$temp_socket" ]; then
            break
        fi
        sleep 1
        attempt=$((attempt + 1))
    done
    
    if [ "$attempt" -eq "$max_attempts" ]; then
        log_message "ERROR" "Failed to start server in safe mode"
        kill -9 "$safe_pid" 2>/dev/null
        rm -f "$temp_socket" "$temp_pid"
        return 1
    fi
    
    # Find SQL client
    local sql_client=""
    if [ "$sql_engine" = "mariadb" ]; then
        if [ -f "${SQL_DIR}/bin/mariadb" ]; then
            sql_client="${SQL_DIR}/bin/mariadb"
        elif [ -f "${SQL_DIR}/bin/mysql" ]; then
            sql_client="${SQL_DIR}/bin/mysql"
        fi
    else
        sql_client="${SQL_DIR}/bin/mysql"
    fi
    
    if [ -z "$sql_client" ]; then
        log_message "ERROR" "SQL client not found"
        kill -9 "$safe_pid" 2>/dev/null
        rm -f "$temp_socket" "$temp_pid"
        return 1
    fi
    
    log_message "INFO" "Resetting root user authentication..."
    
    # Reset authentication based on engine type
    if [ "$sql_engine" = "mariadb" ]; then
        # For MariaDB, set up native password authentication
        "$sql_client" -u root --socket="$temp_socket" <<EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('');
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
FLUSH PRIVILEGES;
EOF
    else
        # For MySQL
        "$sql_client" -u root --socket="$temp_socket" <<EOF
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost', '127.0.0.1', '::1');
FLUSH PRIVILEGES;
EOF
    fi
    
    local reset_result=$?
    
    # Stop safe mode server
    log_message "INFO" "Stopping safe mode server..."
    kill -TERM "$safe_pid" 2>/dev/null
    sleep 2
    if kill -0 "$safe_pid" 2>/dev/null; then
        kill -9 "$safe_pid" 2>/dev/null
    fi
    
    # Clean up temp files
    rm -f "$temp_socket" "$temp_pid"
    
    if [ "$reset_result" -eq 0 ]; then
        log_message "SUCCESS" "Authentication reset successfully!"
        log_message "INFO" "Root user now has no password and uses native password authentication"
        log_message "INFO" "You can now start the server and connect:"
        echo "  sqmate start"
        echo "  sqmate connect"
    else
        log_message "ERROR" "Failed to reset authentication"
        return 1
    fi
    
    return 0
}

# Function: shows recent logs
show_logs() {
    local error_log="${SQL_DIR}/logs/mysqld_error.log"
    local engine_name="${SQL_ENGINE^}"
    
    if [ -f "$error_log" ]; then
        log_message "INFO" "Recent ${engine_name} error log entries ($error_log):"
        echo "----------------------------------------"
        tail -20 "$error_log"
        echo "----------------------------------------"
    else
        log_message "WARNING" "${engine_name} error log file not found: $error_log"
        log_message "INFO" "Server may not be initialized. Run 'sqmate init' first."
    fi
}

# --- Main Script Execution ---

# Function: main entry point
main() {
    # Extract command and shift arguments
    local command=${1:-}
    [ -n "$command" ] && shift

    # Load default configuration
    load_config || return $?

    # Process command-line options
    parse_options "$@" || return $?

    # Execute specified command
    case "$command" in
        init)
            init_sql
            ;;
        start)
            start_server
            ;;
        stop)
            stop_server
            ;;
        restart)
            restart_server
            ;;
        status)
            check_status
            ;;
        config)
            show_config
            ;;
        connect)
            connect_sql
            ;;
        logs)
            show_logs
            ;;
        reset-auth)
            reset_auth
            ;;
        version)
            show_version
            ;;
        help | --help | -h)
            usage
            ;;
        "")
            usage
            return 1
            ;;
        *)
            log_message "ERROR" "Unknown command: $command"
            usage
            return 1
            ;;
    esac

    # Return command execution status
    return $?
}

# Execute main function with all arguments
main "$@"
exit $?