# DNS Watchdog Failover Script

A bash script that monitors multiple servers and automatically updates DNS records to failover to healthy servers. Features real-time monitoring display and quorum-based decision making for high availability.

## Features

- **Real-time Server Monitoring**: Continuously monitors servers using configurable health checks
- **Automatic DNS Failover**: Updates DNS records when the current server becomes unavailable
- **Priority-based Server Selection**: Servers are ordered by priority (highest to lowest)
- **Quorum-based Decision Making**: Requires majority votes from watchdog instances for failover
- **Live Status Dashboard**: Shows server status with color-coded indicators and voting information
- **Graceful Shutdown**: Proper cleanup on exit (Ctrl+C)
- **Comprehensive Logging**: Logs all activities to `/var/log/watchdog.log`
- **Intelligent Failback**: Automatically switches to higher priority servers when they recover

## Files

- `watchdog.sh` - Main script (v1.0)
- `watchdog.cfg` - Configuration file

## Configuration

Edit `watchdog.cfg` to customize settings:

```bash
# DNS Settings
DNS_SERVER="127.0.0.1"
ZONE="example.com" 
RECORD="test.example.com"

# Monitoring Method
method="ping"           # Supports: ping, https, port
ping_count=1
ping_timeout=1

# Alternative methods
#method="https"
#curl_timeout=2
#method="port"
#port=80

# Quorum Settings
#listen_port=25565      # Default: 25565

# Server List (priority order: highest to lowest)
ips=("172.16.0.10" "127.0.0.1" "8.8.8.8")

# Watchdog Instances for Voting
wdips=("172.16.0.3" "172.16.0.4")

# Proposal Frequency (cycles before sending proposal)
n=5
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
   - Starts TCP listener on configured port (default: 25565)
   - Initializes logging to `/var/log/watchdog.log`
   - Finds best available server to start with

2. **Monitoring Loop**: 
   - Checks all servers every 0.5 seconds using configured method
   - Displays real-time status (UP=green, DOWN=red)
   - Shows current active server with asterisk (*)

3. **Failover Logic**:
   - **Downward Failover**: When current server fails, proposes next available server
   - **Upward Failback**: Automatically switches to higher priority servers when they recover  
   - **Proposal System**: Sends proposals every `n` cycles (configurable)
   - **Majority Voting**: Requires majority of watchdog instances to agree before DNS update
   - **Intelligent Selection**: Always selects highest priority available server

4. **DNS Update**: Uses `nsupdate` to change A record with 60-second TTL

## Display

The script shows a live dashboard:

```
===============================================
DNS Watchdog - Active: 172.16.0.10
DNS Server: 127.0.0.1 | Zone: example.com
Record: test.example.com
Method: ping | Quorum: 2/2
===============================================
Votes: next=0, propose=0 (need 2)

* 172.16.0.10           UP
  127.0.0.1             DOWN  
  8.8.8.8               UP

-----------------------------------------------
Last logs:
[2025-06-20 10:30:15] INFO - Starting DNS watchdog
[2025-06-20 10:30:16] INFO - Using configuration from ./watchdog.cfg
[2025-06-20 10:30:20] WARNING - Current server 172.16.0.10 is down
```

## Quorum Communication

- **Listening**: TCP socket on configured port (default: 25565)
- **Voting Commands**: 
  - `propose <IP>` - Propose switching to specific IP
  - `next` - Legacy command for next server (deprecated)
  - `force <IP>` - Force immediate DNS update (admin use)
- **Decision Making**: Requires majority of `wdips` instances to vote
- **Targets**: Sends proposals to all IPs listed in `wdips` array

## Monitoring Methods

Choose monitoring method in config:

- **ping**: ICMP ping check (default)
- **https**: HTTPS connectivity test  
- **port**: TCP port connectivity check

The script uses the selected method for all health checks and failover decisions.

## Voting System

- **Majority Threshold**: `(number_of_watchdogs / 2) + 1`
- **Proposal Frequency**: Controlled by `n` parameter (cycles between proposals)
- **Vote Types**:
  - `propose` votes: For switching to specific IP
  - `next` votes: Legacy support (still functional)
- **Validation**: Only IPs from the configured `ips` array can be proposed

## Current Behavior

- **Server Selection**: Always selects highest priority available server
- **Failover Trigger**: When current server fails health check
- **Failback Trigger**: When higher priority server becomes available
- **Vote Requirement**: Majority of watchdog instances must agree
- **DNS Update**: Updates A record with 60-second TTL
- **Logging**: All events logged with timestamps and severity levels

## Troubleshooting

**Script won't start**:
- Check if required dependencies are installed
- Verify configured port is not in use: `netstat -tlnp | grep 25565`
- Ensure write permissions for `/var/log/watchdog.log`

**DNS updates failing**:
- Verify `nsupdate` has permissions to update the DNS zone
- Check DNS server configuration and zone settings
- Ensure DNS server allows dynamic updates

**Connection issues**:
- Check if watchdog IPs in `wdips` are reachable
- Verify firewall rules allow TCP connections on configured port
- Test connectivity: `telnet <watchdog_ip> 25565`

**Voting issues**:
- Ensure all watchdog instances have same `wdips` configuration
- Check logs for proposal/vote messages
- Verify majority threshold calculation

**Orphaned processes**:
- If script exits improperly: `pkill socat`
- Always use Ctrl+C to exit, not Ctrl+Z
- Check for listeners: `lsof -i :25565`

## Advanced Features

**Manual Commands**:
Send commands directly to running instances:
```bash
# Propose specific IP
echo "propose 8.8.8.8" | socat - TCP:172.16.0.3:25565

# Force immediate update (use with caution)
echo "force 1.1.1.1" | socat - TCP:172.16.0.3:25565
```

**Configuration Tips**:
- Set `n=1` for immediate proposals (testing)
- Set `n=10` for less aggressive switching (production)
- Use odd number of watchdog instances to avoid split votes
- Order `ips` array by preference (highest to lowest priority)

## Planned Features

- ✅ Basic server monitoring and DNS failover
- ✅ Quorum-based decision making  
- ✅ Real-time status display with logging
- ✅ Intelligent failback to higher priority servers
- ✅ Configurable monitoring methods
- ✅ Majority-based voting system
- 🚧 **Coming Next** (maybe):
  - Web-based dashboard
  - Configuration file hot-reload
  - Multi-zone DNS support
  - Health check scoring/weighting
  - Email/webhook notifications
  - Performance metrics collection

## License

This script is provided as-is for educational and operational use.
