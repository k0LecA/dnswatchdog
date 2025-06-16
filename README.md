# dnswatchdog
# DNS Watchdog Failover Script

A bash script that monitors multiple servers and automatically updates DNS records to failover to healthy servers. Features real-time monitoring display and quorum-based decision making for high availability.

## Features

- **Real-time Server Monitoring**: Continuously monitors servers using ping and HTTPS checks
- **Automatic DNS Failover**: Updates DNS records when the current server becomes unavailable
- **Priority-based Server Selection**: Servers are ordered by priority (highest to lowest)
- **Quorum Listening**: Receives votes from other watchdog instances via TCP socket
- **Live Status Display**: Shows server status with color-coded indicators
- **Graceful Shutdown**: Proper cleanup on exit (Ctrl+C)
- **Comprehensive Logging**: Logs all activities to `/var/log/watchdog.log`

## Files

- `watchdog.sh` - Main script
- `watchdog.cfg` - Configuration file

## Configuration

Edit `watchdog.cfg` to customize settings:

```bash
# DNS Settings
DNS_SERVER="127.0.0.1"
ZONE="example.com" 
RECORD="test.example.com"

# Monitoring Method
method="ping"           # Currently supports ping and https checks
ping_count=1
ping_timeout=1

# Alternative methods (commented out by default)
#method="https"
#curl_timeout=2
#method="port"
#port=80

# Quorum Settings
#listen_port=25565      # Default: 25565

# Server List (priority order: highest to lowest)
ips=("172.16.0.32" "1.1.1.1" "8.8.8.8")
```

## Requirements

- `socat` - for TCP socket communication
- `nsupdate` - for DNS record updates
- `curl` - for HTTPS health checks
- `nc` (netcat) - for port checks
- `ping` - for ICMP health checks
- `tput` - for terminal display formatting

Install dependencies:
```bash
# Ubuntu/Debian
sudo apt-get install socat bind9-utils curl netcat-openbsd iputils-ping ncurses-bin

# CentOS/RHEL
sudo yum install socat bind-utils curl nmap-ncat iputils ncurses
```

## Usage

1. Make script executable:
   ```bash
   chmod +x watchdog.sh
   ```

2. Configure your settings in `watchdog.cfg`

3. Run the script:
   ```bash
   ./watchdog.sh
   ```

4. Stop gracefully:
   ```bash
   # Press Ctrl+C (not Ctrl+Z)
   ```

## How It Works

1. **Initialization**: 
   - Reads configuration from `watchdog.cfg`
   - Checks for required dependencies
   - Starts TCP listener on port 25565 (configurable)
   - Initializes logging to `/var/log/watchdog.log`

2. **Monitoring Loop**: 
   - Checks all servers every 0.5 seconds using both ping and HTTPS
   - Displays real-time status (green=ok, red=down)
   - Monitors current active server (pointer-based system)

3. **Failover Logic**:
   - When current server fails, sends "next" message to other instances
   - Collects votes from other watchdog instances via TCP
   - Updates DNS when vote threshold is met (currently >2 votes)
   - Moves to next server in priority list

4. **DNS Update**: Uses `nsupdate` to change A record to next available server

## Display

The script shows a live dashboard:

```
-----------------------------------------------
test.example.com -> 172.16.0.32
DNS_SERVER: 127.0.0.1
ping_timeout: 1
-----------------------------------------------

   IP               ping    https
172.16.0.32         ok      ok
1.1.1.1            down     down
8.8.8.8             ok      ok

-----------------------------------------------
Last logs:
[2025-06-16 10:30:15] INFO - Starting dns watchdog
[2025-06-16 10:30:16] INFO - Using configuration from ./watchdog.cfg
[2025-06-16 10:30:20] WARNING - 172.16.0.32 not responding, sending request to change.
```

## Quorum Communication

- **Listening**: TCP socket on port 25565 (configurable via `listen_port`)
- **Voting**: Sends "next" messages to trigger failover voting
- **Decision Making**: Requires >2 votes to trigger DNS failover
- **Target**: Currently hardcoded to send requests to `172.16.0.3:25565`

## Monitoring Methods

The script performs dual monitoring:

- **ping**: ICMP ping check (always enabled)
- **https**: HTTPS connectivity test (always enabled)
- **port**: TCP port connectivity (implemented but not currently used)

Note: Currently both ping and HTTPS checks are performed regardless of the `method` setting in the config.

## Current Behavior

- **Server Selection**: Uses pointer-based system starting with first server in list
- **Failover Trigger**: When current server fails ping check
- **Vote Requirement**: >2 votes needed for DNS update
- **DNS Update**: Updates A record with 60-second TTL
- **Logging**: All events logged to `/var/log/watchdog.log` with timestamps

## Troubleshooting

**Script won't start**:
- Check if required dependencies are installed
- Verify port 25565 is not in use: `netstat -tlnp | grep 25565`
- Ensure write permissions for `/var/log/watchdog.log`

**DNS updates failing**:
- Verify `nsupdate` has permissions to update the DNS zone
- Check DNS server configuration and zone settings
- Ensure DNS server allows dynamic updates

**Connection issues**:
- Check if target IP `172.16.0.3:25565` is reachable for voting
- Verify firewall rules allow TCP connections on port 25565

**Orphaned processes**:
- If script exits improperly: `pkill socat`
- Always use Ctrl+C to exit, not Ctrl+Z
- Check for temporary files: `ls /tmp/tmp.*`

## Known Limitations

- Vote target IP is hardcoded to `172.16.0.3:25565`
- Method selection in config doesn't affect actual monitoring (both ping and HTTPS always run)
- No automatic fallback to higher priority servers when they recover
- Port monitoring method implemented but not integrated into main loop

## Planned Features

- ✅ Basic server monitoring and DNS failover
- ✅ Quorum-based decision making
- ✅ Real-time status display with logging
- 🚧 **Coming Next**: 
  - Configurable vote targets (remove hardcoded IP)
  - Proper method selection implementation
  - Voting mechanism to return to higher priority servers
  - Configurable vote thresholds
  - Health check scoring system
  - Recovery monitoring for failed servers

## License

This script is provided as-is for educational and operational use.
