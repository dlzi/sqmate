#!/usr/bin/env bash
# ==============================================================================
# sqmate — Universal SQL Server Manager
# ==============================================================================
#
# Manages portable MySQL and MariaDB installations for local development.
# Supports multiple concurrent profiles (each with its own port, socket, and
# config), auto-detects engine type, and handles process lifecycle safely.
#
# Usage:
#   sqmate <command> [options] [<host>:<port>]
#
# Commands:
#   init        Initialise data directory and save installation path
#   start       Start the SQL server          (default: localhost:3306)
#   stop        Stop the running server
#   restart     Restart the server
#   status      Show server status
#   logs        Tail the engine error log
#   reset-auth  Reset root authentication (fixes broken-login situations)
#   version     Print version information
#   help        Print this help text
#
# Options:
#   --sql-dir=<path>   Path to the MySQL/MariaDB installation directory
#   --profile=<name>   Named configuration profile (default: "default")
#   --host=<addr>      Bind address              (default: localhost)
#   --port=<n>         TCP port                  (default: 3306)
#
# Examples:
#   sqmate init --sql-dir=/opt/mariadb-11.4
#   sqmate start
#   sqmate start --port=3307 --profile=mariadb11
#   sqmate start --profile=mysql8 --port=3308
#   sqmate stop   --profile=mysql8
#
# Profile workflow (two engines side-by-side):
#   sqmate init  --profile=mysql8    --sql-dir=/opt/mysql-8.0.39
#   sqmate start --profile=mysql8    --port=3306
#   sqmate init  --profile=mariadb11 --sql-dir=/opt/mariadb-11.4
#   sqmate start --profile=mariadb11 --port=3307
#
# Environment:
#   SQMATE_CONFIG_DIR   Override config directory (default: ~/.config/sqmate)
#
# Supported engines:
#   MySQL   5.7, 8.0, 8.1+
#   MariaDB 10.3, 10.4, 10.5, 10.6, 10.11, 11.x+
#
# Author:  Daniel Zilli
# Version: 1.2.0
# License: Copyright (C) 2025 Daniel Zilli. All rights reserved.
# ==============================================================================

# Abort on unset variables, unhandled errors, and pipeline failures.
set -euo pipefail

# ==============================================================================
# CONSTANTS & DEFAULTS
# ==============================================================================

readonly VERSION="1.2.0"

# Runtime state — may be overridden by load_config / parse_options.
SQL_HOST="localhost"
SQL_PORT="3306"
SQL_DIR=""
SQL_ENGINE=""   # "mysql" or "mariadb"; populated by detect_sql_engine
SQL_BIN=""      # Absolute path to mysqld / mariadbd binary

PROFILE="default"
CONFIG_DIR="${SQMATE_CONFIG_DIR:-${HOME}/.config/sqmate}"

# File paths are re-derived whenever PROFILE or SQL_PORT change.
CONFIG_FILE="${CONFIG_DIR}/config_${PROFILE}"
PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}.pid"
SERVER_PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}_${SQL_PORT}.server.pid"
LOGFILE="${CONFIG_DIR}/sqmate_${PROFILE}.log"
SOCKET_FILE="/tmp/sqmate_${PROFILE}_${SQL_PORT}.sock"

# ANSI colours — defined once, referenced by log_message.
declare -r COLOR_INFO='\033[0;34m'
declare -r COLOR_SUCCESS='\033[0;32m'
declare -r COLOR_WARNING='\033[0;33m'
declare -r COLOR_ERROR='\033[0;31m'
declare -r COLOR_RESET='\033[0m'

# Ensure the config directory exists before any log_message call writes to it.
mkdir -p "${CONFIG_DIR}" 2>/dev/null || {
    printf "[ERROR] Cannot create config directory: %s\n" "${CONFIG_DIR}" >&2
    exit 1
}

# ==============================================================================
# OUTPUT HELPERS
# ==============================================================================

# log_message — write a levelled message to the log file and to the terminal.
#
#   $1  level    — INFO | SUCCESS | WARNING | ERROR
#   $2  message  — human-readable text
log_message() {
    local level="$1"
    local message="$2"

    case "${level^^}" in
        INFO)    printf "%b[INFO]%b    %s\n" "$COLOR_INFO"    "$COLOR_RESET" "$message" ;;
        SUCCESS) printf "%b[SUCCESS]%b %s\n" "$COLOR_SUCCESS" "$COLOR_RESET" "$message" ;;
        WARNING) printf "%b[WARNING]%b %s\n" "$COLOR_WARNING" "$COLOR_RESET" "$message" >&2 ;;
        ERROR)   printf "%b[ERROR]%b   %s\n" "$COLOR_ERROR"   "$COLOR_RESET" "$message" >&2 ;;
        *)       printf "%s\n" "$message" ; return 0 ;; # Exit early for unknown/debug levels
    esac

    # Append to log file using Bash 4.2+ native time formatting (no subshell forks)
    if [[ -n "${LOGFILE:-}" ]]; then
        printf "[%(%Y-%m-%d %H:%M:%S)T] [%-7s] [PID:%d] %s\n" "-1" "${level^^}" "$$" "$message" >> "$LOGFILE" 2>/dev/null || true
    fi
}

# usage — print the full help text to stdout.
usage() {
    cat <<'EOF'

sqmate — Universal SQL Server Manager

Usage:
    sqmate <command> [options] [<host>:<port>]

Commands:
    init        Initialise data directory and save installation path
    start       Start the SQL server          (default: localhost:3306)
    stop        Stop the running server
    restart     Restart the server
    status      Show live server status (PID, socket, uptime)
    logs        Tail the engine error log
    reset-auth  Reset root authentication (fixes broken-login situations)
    version     Print version information
    help        Print this help text

Options:
    --sql-dir=<path>   Path to the MySQL/MariaDB installation directory
    --profile=<name>   Named configuration profile (default: "default")
    --host=<addr>      Bind address              (default: localhost)
    --port=<n>         TCP port                  (default: 3306)

Examples:
    sqmate init --sql-dir=/opt/mariadb-11.4
    sqmate start
    sqmate start --port=3307 --profile=mariadb11
    sqmate stop   --profile=mysql8

Profile workflow (two engines side-by-side):
    sqmate init  --profile=mysql8    --sql-dir=/opt/mysql-8.0.39
    sqmate start --profile=mysql8    --port=3306
    sqmate init  --profile=mariadb11 --sql-dir=/opt/mariadb-11.4
    sqmate start --profile=mariadb11 --port=3307

Environment:
    SQMATE_CONFIG_DIR   Override config directory (default: ~/.config/sqmate)

Supported engines:
    MySQL   5.7, 8.0, 8.1+
    MariaDB 10.3, 10.4, 10.5, 10.6, 10.11, 11.x+

EOF
}

# show_version — print engine/version banner.
show_version() {
    printf "sqmate — Universal SQL Server Manager\n"
    printf "Version : %s\n" "$VERSION"
    printf "Engines : MySQL and MariaDB portable installations\n"
}

# ==============================================================================
# FLAGS & OPTION PARSING
# ==============================================================================

# parse_hostport — parse an optional positional "<host>:<port>" argument.
#
#   $1  hostport  — one of:  host:port | :port | host | port | [IPv6]:port
#
# Updates the global SQL_HOST / SQL_PORT variables and re-derives SOCKET_FILE.
parse_hostport() {
    local hostport_arg="$1"

    if [[ "$hostport_arg" =~ ^(\[[0-9a-fA-F:]+\]):([0-9]+)$ ]]; then
        validate_hostname "${BASH_REMATCH[1]}" || return 1
        validate_port     "${BASH_REMATCH[2]}" || return 1
        SQL_HOST="${BASH_REMATCH[1]}"
        SQL_PORT="${BASH_REMATCH[2]}"
    elif [[ "$hostport_arg" =~ ^([^:]+):([0-9]+)$ ]]; then
        validate_hostname "${BASH_REMATCH[1]}" || return 1
        validate_port     "${BASH_REMATCH[2]}" || return 1
        SQL_HOST="${BASH_REMATCH[1]}"
        SQL_PORT="${BASH_REMATCH[2]}"
    elif [[ "$hostport_arg" =~ ^:([0-9]+)$ ]]; then
        validate_port "${BASH_REMATCH[1]}" || return 1
        SQL_PORT="${BASH_REMATCH[1]}"
    elif [[ "$hostport_arg" =~ ^([^:]+):?$ ]]; then
        validate_hostname "${BASH_REMATCH[1]}" || return 1
        SQL_HOST="${BASH_REMATCH[1]}"
    elif [[ "$hostport_arg" =~ ^[0-9]+$ ]]; then
        validate_port "$hostport_arg" || return 1
        SQL_PORT="$hostport_arg"
    elif [[ "$hostport_arg" =~ .*:.* ]]; then
        log_message "ERROR" "IPv6 addresses must use bracket notation: [::1]:3306"
        return 1
    else
        log_message "WARNING" "Cannot parse '$hostport_arg' as host:port — using defaults ($SQL_HOST:$SQL_PORT)"
    fi

    # Re-derive the socket path now that port is resolved.
    SOCKET_FILE="/tmp/sqmate_${PROFILE}_${SQL_PORT}.sock"
}

# parse_options — process all named options and the optional positional argument.
parse_options() {
    local arg
    local -a positional=()

    while [[ "$#" -gt 0 ]]; do
        arg="$1"
        case "$arg" in
            --sql-dir=*)
                SQL_DIR="${arg#*=}"
                validate_path "$SQL_DIR" "dir" "SQL directory" || return 1
                ;;
            --profile=*)
                PROFILE="${arg#*=}"
                CONFIG_FILE="${CONFIG_DIR}/config_${PROFILE}"
                PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}.pid"
                SERVER_PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}_${SQL_PORT}.server.pid"
                LOGFILE="${CONFIG_DIR}/sqmate_${PROFILE}.log"
                SOCKET_FILE="/tmp/sqmate_${PROFILE}_${SQL_PORT}.sock"
                ;;
            --host=*)
                SQL_HOST="${arg#*=}"
                validate_hostname "$SQL_HOST" || return 1
                ;;
            --port=*)
                SQL_PORT="${arg#*=}"
                validate_port "$SQL_PORT" || return 1
                SOCKET_FILE="/tmp/sqmate_${PROFILE}_${SQL_PORT}.sock"
                SERVER_PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}_${SQL_PORT}.server.pid"
                ;;
            -*)
                log_message "ERROR" "Unknown option: $arg"
                usage
                return 2
                ;;
            *)
                positional+=("$arg")
                ;;
        esac
        shift
    done

    if [[ "${#positional[@]}" -gt 0 ]]; then
        parse_hostport "${positional[0]}" || return 1
    fi
}

# ==============================================================================
# PATH RESOLUTION & VALIDATION
# ==============================================================================

# validate_path — assert that a filesystem path exists and is the expected type.
validate_path() {
    local path="$1" type="$2" description="$3"

    [[ -z "$path" ]] && return 0

    if [[ "$type" == "file" && ! -f "$path" ]]; then
        log_message "ERROR" "$description not found: '$path'"
        return 1
    elif [[ "$type" == "dir" && ! -d "$path" ]]; then
        log_message "ERROR" "$description not found: '$path'"
        return 1
    fi
}

# validate_hostname — reject strings that cannot be valid hostnames or IP addresses.
validate_hostname() {
    local hostname="$1"
    if [[ "$hostname" =~ ^[a-zA-Z0-9.-]+$               # hostname / IPv4
       || "$hostname" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$  # strict IPv4 (extra check)
       || "$hostname" =~ ^\[[0-9a-fA-F:]+\]$             # [IPv6]
    ]]; then
        return 0
    fi
    log_message "ERROR" "Invalid hostname: '$hostname'"
    return 1
}

# validate_port — ensure a port number is a plain integer in [1, 65535].
validate_port() {
    local port="$1"
    if ! [[ "$port" =~ ^[0-9]+$ ]] || (( port < 1 || port > 65535 )); then
        log_message "ERROR" "Invalid port number: '$port' (must be 1–65535)"
        return 1
    fi
}

# detect_sql_engine — inspect SQL_DIR to determine whether it is a MySQL or MariaDB installation
detect_sql_engine() {
    local mariadbd="${SQL_DIR}/bin/mariadbd"
    local mysqld="${SQL_DIR}/bin/mysqld"

    if [[ -f "$mariadbd" ]]; then
        SQL_ENGINE="mariadb"
        SQL_BIN="$mariadbd"
        return 0
    fi

    if [[ ! -f "$mysqld" ]]; then
        log_message "ERROR" "No mysqld or mariadbd binary found in: ${SQL_DIR}/bin/"
        return 1
    fi

    local ver
    ver=$("$mysqld" --version 2>/dev/null) || {
        log_message "ERROR" "Failed to query version from: $mysqld"
        return 1
    }

    if echo "$ver" | grep -qi "mariadb"; then
        SQL_ENGINE="mariadb"
    elif echo "$ver" | grep -qi "mysql"; then
        SQL_ENGINE="mysql"
    else
        log_message "WARNING" "Engine type ambiguous; defaulting to mysql"
        SQL_ENGINE="mysql"
    fi

    SQL_BIN="$mysqld"
}

# validate_sql — confirm that SQL_DIR is set, exists, and contains an executable binary.
validate_sql() {
    if [[ -z "$SQL_DIR" ]]; then
        log_message "ERROR" "SQL directory not configured. Run 'sqmate init' first."
        return 1
    fi

    validate_path "$SQL_DIR" "dir" "SQL directory" || return 1
    detect_sql_engine || return 1

    if [[ ! -x "$SQL_BIN" ]]; then
        log_message "ERROR" "SQL binary is not executable: $SQL_BIN"
        return 1
    fi
}

# check_port_available — return non-zero if something is already bound to the given port.
check_port_available() {
    local host="$1" port="$2"

    if command -v ss &>/dev/null; then
        if ss -tuln | grep -qE "(${host}|0\.0\.0\.0|\[::\]):${port}[[:space:]]"; then
            log_message "ERROR" "Port ${host}:${port} is already in use."
            return 1
        fi
    elif command -v lsof &>/dev/null; then
        if lsof -i :"$port" -sTCP:LISTEN &>/dev/null; then
            log_message "ERROR" "Port ${host}:${port} is already in use."
            return 1
        fi
    else
        log_message "WARNING" "Neither 'ss' nor 'lsof' found; cannot pre-check port ${host}:${port}."
    fi
}

# check_required_tools — abort early if a core POSIX utility is missing.
check_required_tools() {
    local -a missing=()
    local tool

    for tool in ps kill realpath; do
        command -v "$tool" &>/dev/null || missing+=("$tool")
    done

    if (( ${#missing[@]} > 0 )); then
        log_message "ERROR" "Missing required tools: ${missing[*]}"
        return 1
    fi

    if ! command -v ss &>/dev/null && ! command -v lsof &>/dev/null; then
        log_message "WARNING" "Optional tools 'ss' and 'lsof' not found — port conflict checking disabled."
    fi
}

# ==============================================================================
# STATE PERSISTENCE  (config files + PID files)
# ==============================================================================

# load_config — source the profile config file if it exists.
load_config() {
    local cfg="${CONFIG_DIR}/config_${PROFILE:-default}"

    mkdir -p "$CONFIG_DIR" 2>/dev/null || {
        log_message "ERROR" "Cannot create config directory: $CONFIG_DIR"
        return 1
    }
    chmod 700 "$CONFIG_DIR" 2>/dev/null || log_message "WARNING" "Cannot set permissions on: $CONFIG_DIR"

    if [[ -f "$cfg" ]]; then
        chmod 600 "$cfg" 2>/dev/null || log_message "WARNING" "Cannot set permissions on: $cfg"

        if ! bash -n "$cfg" 2>/dev/null; then
            log_message "ERROR" "Syntax error in config file: $cfg"
            return 1
        fi

        # shellcheck source=/dev/null
        source "$cfg" || {
            log_message "ERROR" "Failed to source config file: $cfg"
            return 1
        }
    else
        log_message "INFO" "No config file found at $cfg — using defaults."
    fi

    CONFIG_FILE="$cfg"

    # Re-derive path variables that embed SQL_PORT (which may have just changed).
    PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}.pid"
    SERVER_PIDFILE="${CONFIG_DIR}/sqmate_${PROFILE}_${SQL_PORT}.server.pid"
    LOGFILE="${CONFIG_DIR}/sqmate_${PROFILE}.log"
    SOCKET_FILE="/tmp/sqmate_${PROFILE}_${SQL_PORT}.sock"
}

# save_config — write the current runtime state to the profile config file.
save_config() {
    mkdir -p "$(dirname "$CONFIG_FILE")" || {
        log_message "ERROR" "Cannot create config directory: $(dirname "$CONFIG_FILE")"
        return 1
    }

    local abs_sql_dir
    abs_sql_dir=$(realpath -m "$SQL_DIR" 2>/dev/null) || abs_sql_dir="$SQL_DIR"

    if ! cat > "$CONFIG_FILE" <<EOF
# sqmate configuration — profile: ${PROFILE}
# Auto-generated by sqmate ${VERSION}. Edit with care.
SQL_HOST="${SQL_HOST}"
SQL_PORT="${SQL_PORT}"
SQL_DIR="${abs_sql_dir}"
SQL_ENGINE="${SQL_ENGINE}"
SOCKET_FILE="${SOCKET_FILE}"
EOF
    then
        log_message "ERROR" "Failed to write config file: $CONFIG_FILE"
        return 1
    fi

    chmod 600 "$CONFIG_FILE" || log_message "WARNING" "Cannot set permissions on: $CONFIG_FILE"
}

# _pidfile_create — write a new tracking PID file for the running server.
_pidfile_create() {
    local server_pid="$1"

    local abs_sql_dir
    abs_sql_dir=$(realpath -m "$SQL_DIR" 2>/dev/null) || abs_sql_dir="$SQL_DIR"

    if ! cat > "$PIDFILE" <<EOF
SQL_HOST=${SQL_HOST}
SQL_PORT=${SQL_PORT}
SQL_DIR=${abs_sql_dir}
SQL_ENGINE=${SQL_ENGINE}
DATA_DIR=${abs_sql_dir}/data
SOCKET_FILE=${SOCKET_FILE}
PID=${server_pid}
PROFILE=${PROFILE}
EOF
    then
        log_message "ERROR" "Failed to write PID file: $PIDFILE"
        return 1
    fi

    chmod 600 "$PIDFILE" 2>/dev/null || log_message "WARNING" "Cannot set permissions on: $PIDFILE"
}

# _pidfile_read — read and validate the tracking PID file.
_pidfile_read() {
    [[ -f "$PIDFILE" ]] || return 1

    local content
    content=$(cat "$PIDFILE")

    if ! grep -q '^PID='      <<< "$content" \
    || ! grep -q '^SQL_HOST=' <<< "$content" \
    || ! grep -q '^SQL_PORT=' <<< "$content"; then
        log_message "ERROR" "PID file has invalid format: $PIDFILE"
        rm -f "$PIDFILE" 2>/dev/null
        return 1
    fi

    printf '%s\n' "$content"
}

# _pidfile_get — extract a single value from the tracking PID file.
_pidfile_get() {
    local key="$1"
    local data
    data=$(_pidfile_read) || return 1
    
    local line
    line=$(grep "^${key}=" <<< "$data" 2>/dev/null) || return 1
    
    # Pure bash parameter expansion instead of subshell cut
    printf '%s\n' "${line#*=}"
}

# _pidfile_check — verify that the PID in the tracking file corresponds to a live process.
_pidfile_check() {
    local data server_pid port line
    data=$(_pidfile_read) || return 1

    line=$(grep '^PID=' <<< "$data")
    server_pid="${line#*=}"
    
    line=$(grep '^SQL_PORT=' <<< "$data")
    port="${line#*=}"

    if [[ -z "$server_pid" || ! "$server_pid" =~ ^[0-9]+$ ]]; then
        log_message "WARNING" "Invalid PID in tracking file: $PIDFILE"
        rm -f "$PIDFILE" 2>/dev/null
        return 1
    fi

    if ! kill -0 "$server_pid" 2>/dev/null; then
        log_message "WARNING" "Process $server_pid no longer exists — removing stale PID file."
        rm -f "$PIDFILE" 2>/dev/null
        return 1
    fi

    if command -v lsof &>/dev/null; then
        if ! lsof -i :"$port" -sTCP:LISTEN -t 2>/dev/null | grep -q "^${server_pid}$"; then
            log_message "WARNING" "PID $server_pid is not listening on port $port — removing stale PID file."
            rm -f "$PIDFILE" 2>/dev/null
            return 1
        fi
    fi

    return 0
}

# cleanup_pid_files — remove all tracking and socket files for a given profile.
cleanup_pid_files() {
    local profile="${1:-$PROFILE}"

    rm -f "${CONFIG_DIR}/sqmate_${profile}.pid"        2>/dev/null
    rm -f "${CONFIG_DIR}/sqmate_${profile}_"*.server.pid 2>/dev/null
    rm -f "/tmp/sqmate_${profile}_"*.sock              2>/dev/null
}

# _cleanup_on_exit — trap handler: clean up PID files on SIGINT / SIGTERM.
_cleanup_on_exit() {
    cleanup_pid_files "$PROFILE" 2>/dev/null || true
}
trap '_cleanup_on_exit; exit 1' INT TERM

# ==============================================================================
# VALIDATION — COMPOSITE HELPERS
# ==============================================================================

# find_port_processes — return PIDs of processes listening on a given TCP port.
find_port_processes() {
    local port="$1"
    local -a pids=()
    local pid

    # Replaced mapfile with while-read for compatibility, though on modern
    # systems mapfile is perfectly fine.
    if command -v lsof &>/dev/null; then
        while IFS= read -r pid; do
            [[ -n "$pid" ]] && pids+=("$pid")
        done < <(lsof -i :"$port" -sTCP:LISTEN -t 2>/dev/null)
    elif command -v ss &>/dev/null; then
        while IFS= read -r pid; do
            [[ -n "$pid" ]] && pids+=("$pid")
        done < <(ss -tuln | grep -w "$port" | awk '{print $NF}' | grep -o '[0-9]\+' | sort -u)
    fi

    echo "${pids[@]:-}"
}

# ==============================================================================
# SERVER LIFECYCLE
# ==============================================================================

# prompt_sql_directory — interactively ask the user for the MySQL/MariaDB installation path.
prompt_sql_directory() {
    local current_dir="${SQL_DIR:-}"

    if [[ -n "$current_dir" ]]; then
        log_message "WARNING" "Current SQL directory is missing or invalid: $current_dir"
        printf "Please enter the path to a valid MySQL/MariaDB installation:\n"
    else
        printf "Please enter the path to your MySQL/MariaDB installation directory:\n"
    fi

    printf "(It must contain a 'bin/' subdirectory with mysqld or mariadbd)\n\n"
    IFS= read -r sql_dir_input

    sql_dir_input="${sql_dir_input#"${sql_dir_input%%[![:space:]]*}"}"
    sql_dir_input="${sql_dir_input%"${sql_dir_input##*[![:space:]]}"}"

    if [[ -z "$sql_dir_input" ]]; then
        log_message "ERROR" "SQL directory cannot be empty."
        return 1
    fi

    [[ "$sql_dir_input" == ~* ]] && sql_dir_input="${sql_dir_input/#\~/$HOME}"

    validate_path "$sql_dir_input" "dir" "SQL directory" || return 1

    if [[ ! -f "${sql_dir_input}/bin/mariadbd" && ! -f "${sql_dir_input}/bin/mysqld" ]]; then
        log_message "ERROR" "Not a valid MySQL/MariaDB installation: '$sql_dir_input'"
        log_message "ERROR" "Expected: ${sql_dir_input}/bin/mysqld  or  ${sql_dir_input}/bin/mariadbd"
        return 1
    fi

    SQL_DIR="$sql_dir_input"
}

# initialize_data_directory — run the engine-appropriate data-directory initialisation command.
initialize_data_directory() {
    local data_dir="${SQL_DIR}/data"

    log_message "INFO" "Initialising ${SQL_ENGINE^} data directory: $data_dir"

    if [[ "$SQL_ENGINE" == "mariadb" ]]; then
        local install_db="${SQL_DIR}/scripts/mysql_install_db"

        if [[ -f "$install_db" && -x "$install_db" ]]; then
            log_message "INFO" "Using mysql_install_db script."
            "$install_db" --datadir="$data_dir" --basedir="$SQL_DIR" --user="$(whoami)" || {
                log_message "WARNING" "mysql_install_db failed; falling back to --initialize-insecure."
                "$SQL_BIN" --initialize-insecure --datadir="$data_dir" --basedir="$SQL_DIR" || {
                    log_message "ERROR" "Both MariaDB initialisation methods failed."
                    return 1
                }
            }
        else
            log_message "INFO" "mysql_install_db not found; using mysqld --initialize-insecure."
            "$SQL_BIN" --initialize-insecure --datadir="$data_dir" --basedir="$SQL_DIR" || {
                log_message "ERROR" "Failed to initialise MariaDB data directory."
                return 1
            }
        fi

        log_message "SUCCESS" "MariaDB data directory initialised (no root password set)."
        log_message "INFO" "Set a root password after connecting:"
        log_message "INFO" "  SET PASSWORD FOR 'root'@'localhost' = PASSWORD('yourpass');"

    else
        log_message "INFO" "Using mysqld --initialize (MySQL)."
        "$SQL_BIN" --initialize --datadir="$data_dir" --basedir="$SQL_DIR" || {
            log_message "ERROR" "Failed to initialise MySQL data directory."
            return 1
        }

        log_message "SUCCESS" "MySQL data directory initialised."
        log_message "WARNING" "Temporary root password is in: ${SQL_DIR}/logs/mysqld_error.log"
        log_message "INFO" "Change it after first login:"
        log_message "INFO" "  ALTER USER 'root'@'localhost' IDENTIFIED BY 'yourpass';"
    fi
}

# init_sql — interactive initialisation
init_sql() {
    log_message "INFO" "Initialising sqmate configuration for profile: $PROFILE"

    if [[ -z "$SQL_DIR" ]] || ! validate_sql 2>/dev/null; then
        prompt_sql_directory || return 1
    fi

    validate_sql || return 1
    log_message "SUCCESS" "Detected ${SQL_ENGINE^} installation."

    local data_dir="${SQL_DIR}/data"
    local logs_dir="${SQL_DIR}/logs"

    mkdir -p "$data_dir" "$logs_dir" || {
        log_message "ERROR" "Cannot create data/logs directories under: $SQL_DIR"
        return 1
    }

    if [[ -d "${data_dir}/mysql" ]]; then
        log_message "WARNING" "Data directory already initialised: $data_dir"
    else
        initialize_data_directory || return 1
    fi

    save_config || return 1
    log_message "SUCCESS" "Configuration saved: $CONFIG_FILE"
}

# start_server — start the mysqld/mariadbd process for the current profile.
start_server() {
    validate_sql || return 1
    check_port_available "$SQL_HOST" "$SQL_PORT" || return 1

    local data_dir="${SQL_DIR}/data"
    local logs_dir="${SQL_DIR}/logs"
    local error_log="${logs_dir}/mysqld_error.log"
    local general_log="${logs_dir}/mysqld_general.log"

    validate_path "$data_dir" "dir" "SQL data directory" || {
        log_message "ERROR" "Data directory not found. Run 'sqmate init' first."
        return 1
    }

    if [[ ! -d "${data_dir}/mysql" ]]; then
        log_message "ERROR" "Data directory not initialised. Run 'sqmate init' first."
        return 1
    fi

    mkdir -p "$logs_dir" || {
        log_message "ERROR" "Cannot create logs directory: $logs_dir"
        return 1
    }

    if _pidfile_check; then
        log_message "WARNING" "${SQL_ENGINE^} server is already running. Use 'sqmate restart' to cycle it."
        return 1
    fi

    local daemon_flag=""
    if "$SQL_BIN" --help --verbose 2>/dev/null | grep -q -- '--daemonize'; then
        daemon_flag="--daemonize"
    else
        log_message "INFO" "Engine does not support --daemonize; starting in background."
    fi

    local base_args=(
        --datadir="$data_dir"
        --basedir="$SQL_DIR"
        --socket="$SOCKET_FILE"
        --port="$SQL_PORT"
        --bind-address="$SQL_HOST"
        --pid-file="$SERVER_PIDFILE"
        --log-error="$error_log"
        --general-log
        --general-log-file="$general_log"
    )

    log_message "INFO" "Starting ${SQL_ENGINE^} server on ${SQL_HOST}:${SQL_PORT}"
    log_message "INFO" "  Data dir : $data_dir"
    log_message "INFO" "  Socket   : $SOCKET_FILE"
    log_message "INFO" "  Error log: $error_log"
    [[ "$PROFILE" != "default" ]] && log_message "INFO" "  Profile  : $PROFILE"

    if [[ -n "$daemon_flag" ]]; then
        "$SQL_BIN" "${base_args[@]}" "$daemon_flag" || {
            log_message "ERROR" "Server failed to start. See: $error_log"
            return 1
        }
    else
        "$SQL_BIN" "${base_args[@]}" >/dev/null 2>&1 &
        local bg_pid=$!
        sleep 1
        if ! kill -0 "$bg_pid" 2>/dev/null; then
            log_message "ERROR" "Server exited immediately. See: $error_log"
            return 1
        fi
    fi

    local attempt=0 max_attempts=10 sql_pid=""
    while (( attempt < max_attempts )); do
        if [[ -f "$SERVER_PIDFILE" ]]; then
            sql_pid=$(cat "$SERVER_PIDFILE" 2>/dev/null)
            if [[ -n "$sql_pid" ]] && kill -0 "$sql_pid" 2>/dev/null; then
                break
            fi
        fi
        sleep 1
        (( ++attempt ))
    done

    if [[ -z "$sql_pid" ]] || ! kill -0 "$sql_pid" 2>/dev/null; then
        log_message "ERROR" "Server did not write a valid PID. See: $error_log"
        rm -f "$SERVER_PIDFILE" 2>/dev/null
        return 1
    fi

    _pidfile_create "$sql_pid" || {
        log_message "ERROR" "Cannot write tracking PID file."
        kill "$sql_pid" 2>/dev/null
        return 1
    }

    local port_bound=0
    attempt=0
    while (( attempt < max_attempts )); do
        if command -v lsof &>/dev/null; then
            lsof -i :"$SQL_PORT" -sTCP:LISTEN -t 2>/dev/null \
                | grep -q "^${sql_pid}$" && { port_bound=1; break; }
        elif command -v ss &>/dev/null; then
            ss -tuln \
                | grep -qE "(${SQL_HOST}|0\.0\.0\.0|\[::\]):${SQL_PORT}[[:space:]]" \
                && { port_bound=1; break; }
        else
            port_bound=1
            break
        fi
        sleep 1
        (( ++attempt ))
    done

    if (( port_bound == 0 )); then
        log_message "ERROR" "Server did not bind to port $SQL_PORT. See: $error_log"
        kill "$sql_pid" 2>/dev/null
        cleanup_pid_files "$PROFILE"
        return 1
    fi

    log_message "SUCCESS" "${SQL_ENGINE^} server started (PID: ${sql_pid})."
}

# stop_server — gracefully stop the running server for the current profile.
stop_server() {
    local server_pid sql_host sql_port sql_engine found_server=0

    if _pidfile_check; then
        server_pid=$(_pidfile_get "PID")
        sql_host=$(   _pidfile_get "SQL_HOST")
        sql_port=$(   _pidfile_get "SQL_PORT")
        sql_engine=$( _pidfile_get "SQL_ENGINE")
        found_server=1
    else
        sql_host="$SQL_HOST"
        sql_port="$SQL_PORT"
        sql_engine="${SQL_ENGINE:-SQL}"
        local port_pids
        port_pids=$(find_port_processes "$sql_port")
        if [[ -n "$port_pids" ]]; then
            server_pid="$port_pids"
            found_server=1
        fi
    fi

    if (( found_server == 0 )); then
        log_message "INFO" "No running SQL server found for profile: $PROFILE"
        cleanup_pid_files "$PROFILE"
        return 0
    fi

    local failed=0

    if ! kill -0 "$server_pid" 2>/dev/null; then
        log_message "WARNING" "Process $server_pid already gone."
    else
        log_message "INFO" "Stopping ${sql_engine^} (PID: ${server_pid}) on ${sql_host}:${sql_port}…"

        kill -TERM "$server_pid" 2>/dev/null \
            || log_message "WARNING" "SIGTERM delivery failed for PID $server_pid."

        local attempt=0
        while (( attempt < 30 )) && kill -0 "$server_pid" 2>/dev/null; do
            sleep 1
            (( ++attempt ))
        done

        if kill -0 "$server_pid" 2>/dev/null; then
            log_message "WARNING" "Graceful shutdown timed out; sending SIGKILL to $server_pid."
            kill -9 "$server_pid" 2>/dev/null
            sleep 2
            if kill -0 "$server_pid" 2>/dev/null; then
                log_message "ERROR" "Cannot terminate process $server_pid."
                failed=1
            fi
        fi
    fi

    if command -v lsof &>/dev/null; then
        local port_clear=0 p_attempt=0
        while (( p_attempt < 5 )); do
            lsof -i :"$sql_port" -sTCP:LISTEN &>/dev/null || { port_clear=1; break; }
            sleep 1
            (( ++p_attempt ))
        done
        if (( port_clear == 0 )); then
            log_message "ERROR" "Port ${sql_host}:${sql_port} is still in use after 5 s."
            failed=1
        fi
    fi

    cleanup_pid_files "$PROFILE"

    if (( failed == 0 )); then
        log_message "SUCCESS" "${sql_engine^} server stopped."
        return 0
    else
        log_message "ERROR" "Server did not stop cleanly."
        return 1
    fi
}

# check_status — display live runtime status for the current profile.
check_status() {
    if ! _pidfile_check; then
        log_message "INFO" "No SQL server running for profile: $PROFILE"
        return 1
    fi

    local pid host port dir engine data_dir socket profile start_time

    pid=$(      _pidfile_get "PID")
    host=$(     _pidfile_get "SQL_HOST")
    port=$(     _pidfile_get "SQL_PORT")
    dir=$(      _pidfile_get "SQL_DIR")
    engine=$(   _pidfile_get "SQL_ENGINE")
    data_dir=$( _pidfile_get "DATA_DIR")
    socket=$(   _pidfile_get "SOCKET_FILE")
    profile=$(  _pidfile_get "PROFILE")

    printf "Server Status (%s):\n" "${profile:-default}"
    printf "  %-18s %s\n" "Status:"         "Running"
    printf "  %-18s %s\n" "Engine:"         "${engine^}"
    printf "  %-18s %s\n" "PID:"            "$pid"
    printf "  %-18s %s\n" "URL:"            "${engine}://${host}:${port}/"
    printf "  %-18s %s\n" "Socket File:"    "$socket"
    printf "  %-18s %s\n" "SQL Directory:"  "$dir"
    printf "  %-18s %s\n" "Data Directory:" "$data_dir"
    printf "  %-18s %s\n" "Log File:"       "$LOGFILE"

    if command -v ps &>/dev/null; then
        start_time=$(ps -o lstart= -p "$pid" 2>/dev/null)
        [[ -n "$start_time" ]] \
            && printf "  %-18s %s\n" "Started:" "$start_time"
    fi
}

# restart_server — stop the running server, wait for the port to clear, then start.
restart_server() {
    log_message "INFO" "Restarting SQL server for profile: $PROFILE"

    if _pidfile_check; then
        local s_host s_port s_dir s_engine s_profile
        s_host=$(   _pidfile_get "SQL_HOST")
        s_port=$(   _pidfile_get "SQL_PORT")
        s_dir=$(    _pidfile_get "SQL_DIR")
        s_engine=$( _pidfile_get "SQL_ENGINE")
        s_profile=$(  _pidfile_get "PROFILE")

        [[ -n "$s_host"    ]] && SQL_HOST="$s_host"
        [[ -n "$s_port"    ]] && SQL_PORT="$s_port"
        [[ -n "$s_dir"     ]] && SQL_DIR="$s_dir"
        [[ -n "$s_engine"  ]] && SQL_ENGINE="$s_engine"
        [[ -n "$s_profile" ]] && PROFILE="$s_profile"

        log_message "INFO" "Restoring: engine=${SQL_ENGINE^}  dir=$SQL_DIR  addr=${SQL_HOST}:${SQL_PORT}"
    else
        log_message "WARNING" "No live server found — restarting with current settings."
    fi

    # stop_server inherently verifies that the port is freed before returning.
    stop_server

    start_server || return 1
    log_message "SUCCESS" "SQL server restarted."
}

# reset_auth — start the server in skip-grant-tables mode and reset the root password.
reset_auth() {
    validate_sql || return 1

    local data_dir="${SQL_DIR}/data"

    log_message "INFO" "Resetting ${SQL_ENGINE^} root authentication for profile: $PROFILE"

    if _pidfile_check; then
        log_message "INFO" "Stopping running server first…"
        stop_server || {
            log_message "ERROR" "Cannot stop running server — aborting."
            return 1
        }
    fi

    sleep 2

    local temp_socket="/tmp/sqmate_reset_$$.sock"
    local temp_pid="/tmp/sqmate_reset_$$.pid"

    log_message "INFO" "Starting server in skip-grant-tables / skip-networking mode…"
    "$SQL_BIN" \
        --skip-grant-tables \
        --skip-networking \
        --socket="$temp_socket" \
        --pid-file="$temp_pid" \
        --datadir="$data_dir" \
        --basedir="$SQL_DIR" &
    local safe_pid=$!

    local attempt=0
    while (( attempt < 15 )); do
        [[ -S "$temp_socket" ]] && break
        sleep 1
        (( ++attempt ))
    done

    if (( attempt >= 15 )); then
        log_message "ERROR" "Safe-mode server did not start within 15 s."
        kill -9 "$safe_pid" 2>/dev/null
        rm -f "$temp_socket" "$temp_pid"
        return 1
    fi

    local client=""
    if [[ "$SQL_ENGINE" == "mariadb" ]]; then
        if   [[ -f "${SQL_DIR}/bin/mariadb" ]]; then client="${SQL_DIR}/bin/mariadb"
        elif [[ -f "${SQL_DIR}/bin/mysql"   ]]; then client="${SQL_DIR}/bin/mysql"
        fi
    else
        client="${SQL_DIR}/bin/mysql"
    fi

    if [[ -z "$client" ]]; then
        log_message "ERROR" "SQL client binary not found."
        kill -9 "$safe_pid" 2>/dev/null
        rm -f "$temp_socket" "$temp_pid"
        return 1
    fi

    log_message "INFO" "Applying authentication reset…"

    local reset_sql
    if [[ "$SQL_ENGINE" == "mariadb" ]]; then
        reset_sql="
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost'
    IDENTIFIED VIA mysql_native_password USING PASSWORD('');
DELETE FROM mysql.user
    WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
FLUSH PRIVILEGES;"
    else
        reset_sql="
FLUSH PRIVILEGES;
ALTER USER 'root'@'localhost' IDENTIFIED BY '';
DELETE FROM mysql.user
    WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
FLUSH PRIVILEGES;"
    fi

    "$client" -u root --socket="$temp_socket" <<< "$reset_sql"
    local reset_rc=$?

    log_message "INFO" "Shutting down safe-mode server…"
    kill -TERM "$safe_pid" 2>/dev/null
    sleep 2
    kill -0 "$safe_pid" 2>/dev/null && kill -9 "$safe_pid" 2>/dev/null
    rm -f "$temp_socket" "$temp_pid"

    if (( reset_rc == 0 )); then
        log_message "SUCCESS" "Root authentication reset — no password, native plugin."
        log_message "INFO" "Next steps:"
        printf "  sqmate start\n  sqmate connect\n"
    else
        log_message "ERROR" "Authentication reset failed (SQL client returned $reset_rc)."
        return 1
    fi
}

# show_logs — tail the engine error log (last 20 lines).
show_logs() {
    local error_log="${SQL_DIR}/logs/mysqld_error.log"
    local engine_label="${SQL_ENGINE^}"

    if [[ -f "$error_log" ]]; then
        log_message "INFO" "${engine_label} error log — last 20 lines ($error_log):"
        printf -- '%.0s-' {1..60}; printf '\n'
        tail -20 "$error_log"
        printf -- '%.0s-' {1..60}; printf '\n'
    else
        log_message "WARNING" "${engine_label} error log not found: $error_log"
        log_message "INFO"    "Run 'sqmate init' to initialise the data directory."
    fi
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

# main — parse the command name, load config, validate tooling, process options,
# and dispatch to the appropriate lifecycle function.
main() {
    local command="${1:-}"
    [[ -n "$command" ]] && shift

    load_config || return $?

    if [[ "$command" != "help" && "$command" != "version" \
       && "$command" != "--help" && "$command" != "-h" ]]; then
        check_required_tools || return $?
    fi

    parse_options "$@" || return $?

    case "$command" in
        init)       init_sql      ;;
        start)      start_server  ;;
        stop)       stop_server   ;;
        restart)    restart_server ;;
        status)     check_status  ;;
        logs)       show_logs     ;;
        reset-auth) reset_auth    ;;
        version)    show_version  ;;
        help|--help|-h) usage     ;;
        "")
            usage
            return 1
            ;;
        *)
            log_message "ERROR" "Unknown command: '$command'"
            usage
            return 1
            ;;
    esac
}

main "$@"
exit $?