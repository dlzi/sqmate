# SQMATE - Universal SQL Server Manager

SQMATE is a lightweight command-line utility that simplifies management of portable MySQL and MariaDB installations for local development. It automatically detects your database engine and streamlines server startup, configuration, and monitoring with sensible defaults and multiple profile support.

## Features

- **Universal Support**: Works with both MySQL and MariaDB installations automatically
- **Auto-Detection**: Automatically detects whether you're using MySQL or MariaDB
- **Server Management**: Start, stop, restart, and check status of database servers
- **Multiple Profiles**: Create and manage different server configurations with the `--profile` option
- **Portable Installation Support**: Manage database installations anywhere on your system
- **Automatic Initialization**: Initialize database data directories with guided setup
- **Engine-Specific Initialization**: 
  - MySQL: Uses `mysqld --initialize` (generates temporary root password)
  - MariaDB: Uses `mysql_install_db` or `mysqld --initialize-insecure` (no password)
- **Custom Host/Port**: Run servers on custom hostnames and ports
- **Socket Connection**: Secure local connections via Unix domain sockets
- **Robust Error Handling**: Comprehensive error checking, validation, and detailed logs
- **Logging**: Detailed logs with configurable verbosity levels (DEBUG, INFO, WARNING, ERROR)
- **Status Monitoring**: View running server status including uptime and process information
- **Multiple Instances**: Run multiple database servers simultaneously on different ports

## Requirements

- **Bash**: Version 4.0 or higher
- **MySQL or MariaDB**: Portable installation (any recent version)
  - MySQL: 5.7, 8.0, 8.1+ 
  - MariaDB: 10.3, 10.4, 10.5, 10.6, 10.11, 11.x+
- **Standard Unix Tools**: ps, kill, ss/lsof (optional for port checking)

## Installation

### Quick Install

1. **Download the script**:
   ```bash
   curl -o sqmate.sh https://raw.githubusercontent.com/yourusername/sqmate/main/sqmate.sh
   ```

2. **Make it executable**:
   ```bash
   chmod +x sqmate.sh
   ```

3. **Install system-wide** (recommended):
   ```bash
   sudo mv sqmate.sh /usr/local/bin/sqmate
   ```

4. **Verify installation**:
   ```bash
   sqmate version
   ```

## Getting Started

### Step 1: Download MySQL or MariaDB

Download a portable installation of your preferred database:

#### MySQL
```bash
# Download MySQL 8.0 (example for Linux x86_64)
wget https://dev.mysql.com/get/Downloads/MySQL-8.0/mysql-8.0.39-linux-glibc2.28-x86_64.tar.xz

# Extract
tar -xf mysql-8.0.39-linux-glibc2.28-x86_64.tar.xz
```

#### MariaDB  
```bash
# Download MariaDB 10.11 (example for Linux x86_64)
wget https://downloads.mariadb.org/rest-api/mariadb/10.11.5/mariadb-10.11.5-linux-systemd-x86_64.tar.gz

# Extract
tar -xzf mariadb-10.11.5-linux-systemd-x86_64.tar.gz
```

### Step 2: Initialize Your Database

Run the initialization command and provide the path to your extracted database:

```bash
# Initialize (you'll be prompted for the database directory path)
sqmate init

# Or specify the directory directly
sqmate init --sql-dir=/opt/mysql-8.0.39-linux-glibc2.28-x86_64
```

SQMATE will automatically:
- ✅ Detect whether it's MySQL or MariaDB
- ✅ Initialize the data directory appropriately
- ✅ Create necessary log directories
- ✅ Save the configuration

### Step 3: Start Your Database Server

```bash
# Start the server (default: localhost:3306)
sqmate start

# Check status
sqmate status

# Connect to your database
sqmate connect
```

That's it! Your database server is now running.

## Usage

### Basic Commands

```bash
# Server control
sqmate start              # Start the database server
sqmate stop               # Stop the server
sqmate restart            # Restart the server
sqmate status             # Check server status

# Database operations
sqmate connect            # Connect to the database
sqmate logs               # View recent error logs

# Configuration
sqmate config             # Show current configuration
sqmate init               # Initialize new database
```

### Advanced Usage

#### Multiple Database Instances

You can run multiple database servers simultaneously using profiles:

```bash
# Set up MySQL on port 3306
sqmate init --profile=mysql8 --sql-dir=/opt/mysql-8.0.39
sqmate start --profile=mysql8 --port=3306

# Set up MariaDB on port 3307
sqmate init --profile=mariadb11 --sql-dir=/opt/mariadb-10.11.5
sqmate start --profile=mariadb11 --port=3307

# Both servers are now running!
sqmate status --profile=mysql8     # Shows MySQL status
sqmate status --profile=mariadb11  # Shows MariaDB status

# Connect to specific database
sqmate connect --profile=mysql8
sqmate connect --profile=mariadb11
```

#### Custom Host and Port

```bash
# Start on all interfaces with custom port
sqmate start --host=0.0.0.0 --port=3307

# Start with hostname:port format
sqmate start localhost:3307
sqmate start 0.0.0.0:3308
```

#### Development Workflow

```bash
# Set up development environment
sqmate init --profile=dev --sql-dir=/path/to/mysql
sqmate start --profile=dev

# Work on your project...
sqmate connect --profile=dev

# View logs when debugging
sqmate logs --profile=dev

# Restart when needed (preserves configuration)
sqmate restart --profile=dev

# Stop when done
sqmate stop --profile=dev
```

## Command Reference

### Commands

| Command | Description |
|---------|-------------|
| `init` | Initialize database data directory and set installation path |
| `start` | Start the database server |
| `stop` | Stop the running server |
| `restart` | Restart the server |
| `status` | Show server status |
| `connect` | Connect to database server |
| `logs` | Show recent error logs |
| `config` | Show current configuration |
| `version` | Show version information |
| `help` | Display help information |

### Options

| Option | Description |
|--------|-------------|
| `--sql-dir=<path>` | Set MySQL/MariaDB installation directory |
| `--profile=<name>` | Use specific configuration profile |
| `--host=<hostname>` | Set database hostname (default: localhost) |
| `--port=<number>` | Set database port (default: 3306) |
| `--debug` | Enable debug logging |

### Examples

```bash
# Basic usage
sqmate init
sqmate start
sqmate connect

# With custom options
sqmate start --host=0.0.0.0 --port=3307
sqmate start --profile=dev --port=3306

# Profile management
sqmate init --profile=mysql8 --sql-dir=/opt/mysql8
sqmate init --profile=mariadb11 --sql-dir=/opt/mariadb11
sqmate start --profile=mysql8
sqmate start --profile=mariadb11

# Multiple servers running simultaneously
sqmate status --profile=mysql8      # Check MySQL status
sqmate status --profile=mariadb11   # Check MariaDB status
```

## Configuration

### File Locations

- **Configuration Directory**: `~/.config/sqmate/`
- **Profile Configurations**: `~/.config/sqmate/config_<profile>`
- **PID Files**: `~/.config/sqmate/sqmate_<profile>.pid`
- **Log Files**: `~/.config/sqmate/sqmate_<profile>.log`
- **Socket Files**: `/tmp/sqmate_<profile>_<port>.sock`

### Profile System

SQMATE uses profiles to manage multiple database configurations:

- **Automatic Creation**: Profiles are created automatically when first used
- **Persistent Storage**: All settings are saved and restored between sessions
- **Isolation**: Each profile has separate configuration, logs, and PID files
- **Multiple Engines**: Run MySQL and MariaDB simultaneously with different profiles

### Environment Variables

| Variable | Description |
|----------|-------------|
| `SQMATE_CONFIG_DIR` | Override default config directory |
| `LOG_LEVEL` | Set logging verbosity (DEBUG, INFO, WARNING, ERROR) |

## Database-Specific Notes

### MySQL

- **Initialization**: Uses `mysqld --initialize`
- **Root Password**: Generates a temporary password (check error log)
- **Password Change**: Required on first connection
  ```sql
  ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';
  ```

### MariaDB

- **Initialization**: Prefers `mysql_install_db`, falls back to `mysqld --initialize-insecure`
- **Root Password**: No password set by default
- **Password Setup**: Optional, can be set after connection
  ```sql
  SET PASSWORD FOR 'root'@'localhost' = PASSWORD('your_password');
  ```

## Troubleshooting

### Common Issues

| Issue | Solution |
|-------|----------|
| "SQL directory not configured" | Run `sqmate init` first |
| "Data directory not initialized" | Run `sqmate init` to create system tables |
| "Port in use" | Another server is running; use different port or `sqmate stop` |
| "Process not found" | Stale PID file; run `sqmate stop` to clean up |
| "Permission denied" | Ensure script is executable: `chmod +x sqmate` |
| "Connection refused" | Check if server is running: `sqmate status` |

### Debugging

```bash
# Enable detailed logging
sqmate start --debug

# Check logs
sqmate logs

# View configuration
sqmate config

# Check database error logs directly
tail -f ~/.config/sqmate/sqmate_<profile>.log
tail -f <sql-dir>/logs/mysqld_error.log
```

### Log Files

- **SQMATE logs**: `~/.config/sqmate/sqmate_<profile>.log`
- **Database error logs**: `<sql-dir>/logs/mysqld_error.log`
- **Database general logs**: `<sql-dir>/logs/mysqld_general.log`

## Advanced Scenarios

### Testing Database Compatibility

```bash
# Set up both MySQL and MariaDB for testing
sqmate init --profile=mysql --sql-dir=/opt/mysql-8.0.39
sqmate init --profile=mariadb --sql-dir=/opt/mariadb-10.11.5

# Start both on different ports
sqmate start --profile=mysql --port=3306
sqmate start --profile=mariadb --port=3307

# Test your application against both
sqmate connect --profile=mysql    # Test with MySQL
sqmate connect --profile=mariadb  # Test with MariaDB
```

### Development Team Setup

```bash
# Each team member can use the same commands
sqmate init --profile=project-dev --sql-dir=/path/to/shared/mysql
sqmate start --profile=project-dev --port=3306

# Consistent development environment across team
```

### Multiple Versions

```bash
# Different MySQL versions
sqmate init --profile=mysql57 --sql-dir=/opt/mysql-5.7.44
sqmate init --profile=mysql80 --sql-dir=/opt/mysql-8.0.39

# Different MariaDB versions  
sqmate init --profile=mariadb103 --sql-dir=/opt/mariadb-10.3.39
sqmate init --profile=mariadb1011 --sql-dir=/opt/mariadb-10.11.5

# Run all simultaneously on different ports
sqmate start --profile=mysql57 --port=3306
sqmate start --profile=mysql80 --port=3307
sqmate start --profile=mariadb103 --port=3308
sqmate start --profile=mariadb1011 --port=3309
```

## Security Considerations

- **Local Binding**: By default, servers bind to localhost only
- **Socket Connections**: Local connections use secure Unix domain sockets
- **Network Access**: Use `--host=0.0.0.0` only when needed for external access
- **Password Management**: Change default passwords immediately after setup
- **File Permissions**: Configuration files are protected with 600 permissions

## License

SQMATE is released under the MIT License.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Author

Based on the design patterns of PHMATE by Daniel Zilli.

---

## Quick Reference Card

```bash
# Setup (one time)
sqmate init --sql-dir=/path/to/database

# Daily usage
sqmate start        # Start server
sqmate connect      # Connect to database  
sqmate stop         # Stop server

# Multiple databases
sqmate start --profile=mysql8 --port=3306
sqmate start --profile=mariadb11 --port=3307

# Troubleshooting
sqmate status       # Check if running
sqmate logs         # View error logs
sqmate restart      # Restart server
```