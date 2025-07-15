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
- **Authentication Reset**: Built-in `reset-auth` command to fix login issues
- **Custom Host/Port**: Run servers on custom hostnames and ports
- **Socket Connection**: Secure local connections via Unix domain sockets
- **GUI Tool Compatible**: Works with database management tools like Navicat, phpMyAdmin, etc.
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

### Using Makefile

If you've cloned the repository, you can use the provided Makefile for a complete installation including documentation and bash completion:

```bash
git clone https://github.com/dlzi/sqmate.git
cd sqmate
make install
```

This will install sqmate to `/usr/local/bin/sqmate` by default. To install to a different location:

```bash
make install PREFIX=~/.local
```

To uninstall sqmate when installed with the Makefile:

```bash
make uninstall
```

### Using install.sh Script

The repository includes an installation script that properly installs all components including documentation and bash completion:

```bash
git clone https://github.com/dlzi/sqmate.git
cd sqmate
./install.sh
```

You can customize the installation directories by setting environment variables:

```bash
PREFIX=~/.local ./install.sh
```

To uninstall sqmate when installed with the install script:

```bash
./uninstall.sh
```

## Getting Started

### Step 1: Download MySQL or MariaDB

Download a portable installation of your preferred database:

#### MySQL
```bash
# Download MySQL 9.x (example for Linux x86_64)
wget https://dev.mysql.com/get/Downloads/MySQL-9.3/mysql-9.3.0-linux-glibc2.28-x86_64.tar.xz

# Extract
tar -xf mysql-9.3.0-linux-glibc2.28-x86_64.tar.xz
```

#### MariaDB  
```bash
# Download MariaDB 11.x (example for Linux x86_64)
wget https://downloads.mariadb.org/rest-api/mariadb/11.8.2/mariadb-11.8.2-linux-systemd-x86_64.tar.gz

# Extract
tar -xzf mariadb-11.8.2-linux-systemd-x86_64.tar.gz
```

### Compatibility Notes

Some portable MySQL/MariaDB binaries may require the `libcrypt.so.1` library. If you encounter library errors, you may need to install compatibility libraries:

- **Arch Linux**: `sudo pacman -S libxcrypt-compat`
- **Ubuntu/Debian**: Usually included by default
- **CentOS/RHEL**: `sudo yum install libxcrypt-compat` or `sudo dnf install libxcrypt-compat`

This provides the `libcrypt.so.1` library needed by portable MySQL/MariaDB binaries.

### Step 2: Initialize Your Database

Run the initialization command and provide the path to your extracted database:

```bash
# Initialize (you'll be prompted for the database directory path)
sqmate init

# Or specify the directory directly
sqmate init --sql-dir=/opt/mariadb-11.8.2-linux-systemd-x86_64
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
sqmate reset-auth         # Fix authentication issues

# Configuration
sqmate config             # Show current configuration
sqmate init               # Initialize new database
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
| `reset-auth` | **Reset database authentication (fixes login issues)** |
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

# Fix authentication issues
sqmate reset-auth

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

## GUI Database Management Tools

SQMATE works seamlessly with database management GUIs like Navicat, phpMyAdmin, DBeaver, etc.

### Connection Settings for GUI Tools:

```
Host: 127.0.0.1  (use IP, not "localhost")
Port: 3306
Username: root
Password: (leave empty)
Connection Type: TCP/IP (not socket)
```

### If GUI Connection Fails:

1. **Reset authentication** (most common fix):
   ```bash
   sqmate reset-auth
   sqmate start
   ```

2. **Verify server is running**:
   ```bash
   sqmate status
   ```

3. **Test command-line connection first**:
   ```bash
   sqmate connect
   ```

4. **Check TCP connectivity**:
   ```bash
   ss -tuln | grep 3306  # Should show MariaDB listening on port 3306
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

- **Binary**: Uses `mysqld`
- **Initialization**: Uses `mysqld --initialize`
- **Root Password**: Generates a temporary password (check error log)
- **Password Change**: Required on first connection
  ```sql
  ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';
  ```

### MariaDB

- **Binary**: Prefers `mariadbd` over `mysqld` (eliminates deprecation warnings)
- **Initialization**: Prefers `mysql_install_db`, falls back to `mysqld --initialize-insecure`
- **Root Password**: No password set by default
- **Authentication**: Uses native password authentication after `reset-auth`
- **Password Setup**: Optional, can be set after connection
  ```sql
  SET PASSWORD FOR 'root'@'localhost' = PASSWORD('your_password');
  ```

## Troubleshooting

### Common Issues and Solutions

| Issue | Solution |
|-------|----------|
| **"SQL directory not configured"** | Run `sqmate init` first |
| **"Data directory not initialized"** | Run `sqmate init` to create system tables |
| **"Port in use"** | Another server is running; use different port or `sqmate stop` |
| **"Process not found"** | Stale PID file; run `sqmate stop` to clean up |
| **"Permission denied"** | Ensure script is executable: `chmod +x sqmate` |
| **"Connection refused"** | Check if server is running: `sqmate status` |
| **"Access denied for user 'root'"** | **Run `sqmate reset-auth` to fix authentication** |
| **GUI tools can't connect** | **Run `sqmate reset-auth` and use TCP/IP connection** |
| **"libcrypt.so.1 not found" (Arch Linux)** | Install: `sudo pacman -S libxcrypt-compat` |
| **Deprecation warnings** | SQMATE automatically uses modern binaries (`mariadbd`, `mariadb`) |

### Authentication Issues (Most Common)

If you can't connect to your database or get "Access denied" errors:

```bash
# Quick fix for most authentication issues
sqmate reset-auth
sqmate start
sqmate connect  # Should work without password
```

The `reset-auth` command:
- ✅ Safely resets root user authentication
- ✅ Sets up native password authentication
- ✅ Removes password requirement
- ✅ Fixes GUI tool connectivity issues

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

# Check if TCP port is listening
ss -tuln | grep 3306
```

### Log Files

- **SQMATE logs**: `~/.config/sqmate/sqmate_<profile>.log`
- **Database error logs**: `<sql-dir>/logs/mysqld_error.log`
- **Database general logs**: `<sql-dir>/logs/mysqld_general.log`

## Security Considerations

- **Local Binding**: By default, servers bind to localhost only
- **Socket Connections**: Local connections use secure Unix domain sockets
- **Network Access**: Use `--host=0.0.0.0` only when needed for external access
- **Password Management**: Use `reset-auth` to set up secure authentication
- **File Permissions**: Configuration files are protected with 600 permissions

## License

SQMATE is released under the MIT License.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests.

## Author

Daniel Zilli.

---

## Quick Reference Card

```bash
# Setup (one time)
sqmate init --sql-dir=/path/to/database

# Daily usage
sqmate start        # Start server
sqmate connect      # Connect to database  
sqmate stop         # Stop server

# Fix authentication issues
sqmate reset-auth   # Fixes most login problems

# Multiple databases
sqmate start --profile=mysql8 --port=3306
sqmate start --profile=mariadb11 --port=3307

# GUI tool setup
# Host: 127.0.0.1, Port: 3306, User: root, Password: (empty)

# Troubleshooting
sqmate status       # Check if running
sqmate logs         # View error logs
sqmate restart      # Restart server
sqmate reset-auth   # Fix authentication
```
