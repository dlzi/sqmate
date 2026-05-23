# Sqmate - SQL Server Manager

Sqmate is a lightweight command-line utility that simplifies management of portable MySQL and MariaDB installations for local development. It automatically detects your database engine and streamlines server startup, configuration, and monitoring with sensible defaults and multiple profile support.

## Features

- **Auto-Detection**: Automatically detects whether you're using MySQL or MariaDB
- **Server Management**: Start, stop, restart, and check status of database servers
- **Multiple Profiles**: Create and manage different server configurations with the `--profile` option
- **Portable Installation Support**: Manage database installations anywhere on your system
- **Manual Initialization**: Initialize database data directories with interactive setup
- **Engine-Specific Initialization**: 
     - MySQL: Uses `mysqld --initialize` (generates temporary root password)
     - MariaDB: Uses `mysql_install_db` or `mysqld --initialize-insecure` (no password)
- **Authentication Reset**: Built-in `reset-auth` command to fix login issues
- **Custom Host/Port**: Run servers on custom hostnames and ports
- **Socket Connection**: Secure local connections via Unix domain sockets
- **GUI Tool Compatible**: Works with database management tools like Navicat, phpMyAdmin, etc.
- **Robust Error Handling**: Comprehensive error checking, validation, and detailed logs
- **Logging**: Detailed operation logs written to `~/.config/sqmate/sqmate_<profile>.log`
- **Status Monitoring**: View running server status including uptime and process information
- **Multiple Instances**: Run multiple database servers simultaneously on different ports

## Requirements

- **Bash**: Version 4.3 or higher
- **MySQL or MariaDB**: Portable installation (any recent version)
- **Standard Unix Tools**: ps, kill, realpath (required), ss/lsof (optional for port checking)
- **Critical Dependency**: `libxcrypt.so.1` library (see Compatibility Notes below)

## Installation

### Using Makefile

If you've cloned the repository, you can use the provided Makefile for a complete installation including documentation and the man page:

```bash
git clone https://github.com/dlzi/sqmate.git
cd sqmate
sudo make install
```

This will install sqmate to `/usr/local/bin/sqmate` by default. To install to a different location (no sudo required):

```bash
make install PREFIX=~/.local
```

To uninstall sqmate when installed with the Makefile:

```bash
sudo make uninstall  # If installed to /usr/local/bin
# or
make uninstall       # If installed to ~/.local
```

### Using install.sh Script

The repository includes an installation script that installs all components including documentation and the man page:

```bash
git clone https://github.com/dlzi/sqmate.git
cd sqmate
sudo ./install.sh    # For system-wide installation
```

For user-local installation without sudo (recommended for development):

```bash
PREFIX="$HOME/.local" ./install.sh
```

To uninstall sqmate when installed with the install script:

```bash
sudo ./uninstall.sh  # If installed system-wide
# or
PREFIX="$HOME/.local" ./uninstall.sh  # If installed to ~/.local
```

## Compatibility Notes

### Critical: libxcrypt.so.1 Required

**⚠️ IMPORTANT**: Portable MySQL/MariaDB binaries require the `libcrypt.so.1` library. Without this library, the database server will **fail to start** with errors like:

```
error while loading shared libraries: libcrypt.so.1: cannot open shared object file
```

**Install the compatibility library BEFORE starting your database:**

- **Arch Linux**: `sudo pacman -S libxcrypt-compat`
- **Ubuntu/Debian**: Usually included by default, but if needed: `sudo apt-get install libxcrypt1`
- **CentOS/RHEL 8+**: `sudo dnf install libxcrypt-compat`
- **CentOS/RHEL 7**: `sudo yum install libxcrypt`

This provides the `libcrypt.so.1` library needed by portable MySQL/MariaDB binaries.

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

### Step 2: Initialize Your Database

**Important**: You can run `sqmate init` from any directory on your system. Sqmate will ask you for (or you can specify) the **full path** to where you extracted the database files.

```bash
# Option 1: Run init and enter the path when prompted
sqmate init
# You'll see: "Please enter the path to your MySQL/MariaDB installation directory:"
# Enter the full path, e.g.: /home/user/mariadb-11.8.2-linux-systemd-x86_64

# Option 2: Specify the directory directly on the command line
sqmate init --sql-dir=/home/user/mariadb-11.8.2-linux-systemd-x86_64

# Option 3: Use relative path (if you're in the parent directory)
sqmate init --sql-dir=./mariadb-11.8.2-linux-systemd-x86_64
```

Sqmate will:

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
sqmate logs               # View recent error logs
sqmate reset-auth         # Fix authentication issues

# Configuration
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
| `logs` | Show recent error logs |
| `reset-auth` | Reset database authentication (fixes login issues) |
| `version` | Show version information |
| `help` | Display help information |

### Options

| Option | Description |
|--------|-------------|
| `--sql-dir=<path>` | Set MySQL/MariaDB installation directory |
| `--profile=<name>` | Named configuration profile; must be initialised with `sqmate init --profile=<name>` before use |
| `--host=<hostname>` | Set database hostname (default: localhost) |
| `--port=<number>` | Set database port (default: 3306) |

### Examples

```bash
# Basic usage - first time setup
sqmate init                                     # Initialize default profile
sqmate start                                    # Start server
sqmate status                                   # Check it's running

# Fix authentication issues
sqmate reset-auth   # Fixes most login problems

# Custom options
sqmate start --host=0.0.0.0 --port=3307
sqmate start --profile=dev --port=3306

# Profile management - each profile needs initialization
sqmate init --profile=mysql8 --sql-dir=/opt/mysql8
sqmate init --profile=mariadb11 --sql-dir=/opt/mariadb11
sqmate start --profile=mysql8 --port=3306
sqmate start --profile=mariadb11 --port=3307

# Check status of specific profiles
sqmate status --profile=mysql8
sqmate status --profile=mariadb11

# Stop specific profile
sqmate stop --profile=mysql8
```

## GUI Database Management Tools

Sqmate works seamlessly with database management GUIs like Navicat, phpMyAdmin, DBeaver, etc.

### Connection Settings for GUI Tools:

```
Host: 127.0.0.1  (use IP, not "localhost")
Port: 3306
Username: root
Password: (leave empty for MariaDB, check logs for MySQL)
Connection Type: TCP/IP (not socket)
```

### If GUI Connection Fails:

1. **Verify server is running** (do this first):
   ```bash
   sqmate status
   ```

2. **Reset authentication** (most common fix):
   ```bash
   sqmate stop
   sqmate reset-auth
   sqmate start
   ```

3. **Test command-line connection**:
   ```bash
   # Connect via socket (path shown by sqmate status)
   mysql -u root -S /tmp/sqmate_default_3306.sock
   # or via TCP
   mysql -u root -h 127.0.0.1 -P 3306
   ```

4. **Check TCP connectivity**:
   ```bash
   ss -tuln | grep 3306  # Should show server listening on port 3306
   # or
   lsof -i :3306         # Alternative command
   ```

5. **Check for library errors**:
   ```bash
   sqmate logs
   # Look for "libcrypt.so.1" errors - install libxcrypt-compat if found
   ```

## Configuration

### File Locations

All configuration files are stored in `~/.config/sqmate/`:

| File Type | Location | Description |
|-----------|----------|-------------|
| **Profile Config** | `~/.config/sqmate/config_<profile>` | Stores SQL_DIR, host, port, engine type, daemonize support |
| **Sqmate PID** | `~/.config/sqmate/sqmate_<profile>.pid` | Tracks sqmate's view of server state |
| **Server PID** | `~/.config/sqmate/sqmate_<profile>_<port>.server.pid` | Actual database server PID |
| **Sqmate Logs** | `~/.config/sqmate/sqmate_<profile>.log` | Sqmate operation logs |
| **Socket File** | `/tmp/sqmate_<profile>_<port>.sock` | Unix domain socket for local connections |
| **Database Logs** | `<sql-dir>/logs/mysqld_error.log` | Database server error log |
| **Query Logs** | `<sql-dir>/logs/mysqld_general.log` | Database query log (if enabled) |

### Profile System

Sqmate uses profiles to manage multiple database configurations:

- **Manual Creation**: Profiles are created when you run `sqmate init --profile=<n>`
- **Requires Initialization**: Each profile must be initialized before use
- **Persistent Storage**: All settings are saved and restored between sessions
- **Isolation**: Each profile has separate configuration, logs, and PID files
- **Multiple Engines**: Run MySQL and MariaDB simultaneously with different profiles

**Important**: A profile must be initialized with `sqmate init --profile=<n>` before you can start a server with that profile.

### Environment Variables

| Variable | Description |
|----------|-------------|
| `SQMATE_CONFIG_DIR` | Override default config directory (~/.config/sqmate) |

## Database-Specific Notes

### MySQL

- **Binary**: Uses `mysqld`
- **Initialization**: Uses `mysqld --initialize`
- **Root Password**: Generates a temporary password (check error log)
- **Password Change**: Required on first connection
  ```sql
  ALTER USER 'root'@'localhost' IDENTIFIED BY 'your_new_password';
  ```
- **Finding Temp Password**: Check `<sql-dir>/logs/mysqld_error.log` for a line containing "temporary password"

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
| **"Access denied for user 'root'"** | Run `sqmate reset-auth` to fix authentication |
| **GUI tools can't connect** | Run `sqmate reset-auth` and use TCP/IP connection (127.0.0.1) |
| **"libcrypt.so.1 not found"** | **CRITICAL**: Install `libxcrypt-compat` (see Compatibility Notes) |
| **Deprecation warnings** | Sqmate automatically uses modern binaries (`mariadbd`, `mariadb`) |
| **Server starts but immediately stops** | Check `sqmate logs` - usually library or permission issues |

### Authentication Issues (Most Common)

If you can't connect to your database or get "Access denied" errors:

```bash
# Quick fix for most authentication issues
sqmate stop
sqmate reset-auth
sqmate start
```

The `reset-auth` command:

- ✅ Safely resets root user authentication
- ✅ Sets up native password authentication
- ✅ Removes password requirement (MariaDB)
- ✅ Fixes GUI tool connectivity issues

### Debugging Steps

1. **Check server status**:
   ```bash
   sqmate status
   ```

2. **View engine error log**:
   ```bash
   sqmate logs
   ```

3. **View sqmate operational log**:
   ```bash
   tail -f ~/.config/sqmate/sqmate_<profile>.log
   ```

4. **View engine error log directly** (for verbose output):
   ```bash
   tail -f <sql-dir>/logs/mysqld_error.log
   ```

5. **View current profile configuration**:
   ```bash
   cat ~/.config/sqmate/config_default
   ```

6. **Check TCP port binding**:
   ```bash
   ss -tuln | grep 3306
   # or
   lsof -i :3306
   ```

7. **Verify library dependencies** (most common startup issue):
   ```bash
   ldd <sql-dir>/bin/mysqld    # or mariadbd
   # Look for "not found" entries - especially libcrypt.so.1
   ```

## Security Considerations

- **Local Binding**: By default, servers bind to localhost only (127.0.0.1)
- **Socket Connections**: Local connections use secure Unix domain sockets
- **Network Access**: Use `--host=0.0.0.0` only when needed for external access
- **Password Management**: 
      - MariaDB: No password by default after `reset-auth`
      - MySQL: Check logs for temporary password after `init`
- **File Permissions**: Configuration files are protected with 600 permissions
- **Multiple Users**: Each user has their own isolated configuration in their home directory

## License

Sqmate is released under the MIT License.

## Contributing

Contributions are welcome! Please feel free to submit issues and pull requests at the GitHub repository.

## Author

Daniel Zilli

---

## Quick Reference Card

```bash
# Setup (one time per profile)
sqmate init --sql-dir=/path/to/database
# Note: Install libxcrypt-compat first on Arch Linux!

# Daily usage
sqmate start        # Start server
sqmate status       # Verify it's running
sqmate stop         # Stop server

# Fix authentication issues
sqmate reset-auth   # Fixes most login problems

# Multiple databases (each needs init first)
sqmate init --profile=mysql8 --sql-dir=/opt/mysql8
sqmate init --profile=mariadb11 --sql-dir=/opt/mariadb11
sqmate start --profile=mysql8 --port=3306
sqmate start --profile=mariadb11 --port=3307

# GUI tool setup
# Host: 127.0.0.1, Port: 3306, User: root
# Password: (empty for MariaDB, check logs for MySQL)

# Troubleshooting
sqmate status       # Check if running
sqmate logs         # View error logs
sqmate restart      # Restart server
sqmate reset-auth   # Fix authentication
```

## Frequently Asked Questions

**Q: Server won't start, error about libcrypt.so.1?**  
A: Install `libxcrypt-compat` or `libxcrypt1` package.

**Q: Do I need to run sqmate with sudo?**  
A: No. Sqmate runs as your user. Only installation to `/usr/local/bin` requires sudo.

**Q: Can I run multiple servers at once?**  
A: Yes! Use different profiles and ports for each instance.

**Q: How do I change the root password?**  
A: Connect using the mysql client (socket path shown by `sqmate status`) then run SQL commands to set a password.

**Q: Where are my database files stored?**  
A: In `<sql-dir>/data/` where `<sql-dir>` is the directory you provided during `init`.

**Q: Can I use this in production?**  
A: Sqmate is designed for local development. For production, use proper database installation with systemd/init scripts.