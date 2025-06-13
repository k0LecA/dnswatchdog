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
method="ping"           # ping, https, or port
ping_count=1
ping_timeout=1

# Server List (priority order: highest to lowest)
ips=("172.16.0.3" "1.1.1.1" "8.8.8.8")

# Quorum Settings
listen_port=25565
```

## Requirements

- `socat` - for TCP socket communication
- `nsupdate` - for DNS record updates
- `curl` - for HTTPS health checks (if using https method)
- `nc` (netcat) - for port checks (if using port method)

Install dependencies:
```bash
# Ubuntu/Debian
sudo apt install socat bind9-dnsutils curl netcat-openbsd

# CentOS/RHEL
sudo yum install socat bind-utils curl nmap-ncat
```

## Usage

1. Make script executable:
   ```bash
   chmod +x watchdog.sh
   ```

2. Run the script:
   ```bash
   ./watchdog.sh
   ```

3. Stop gracefully:
   ```bash
   # Press Ctrl+C (not Ctrl+Z)
   ```

## How It Works

1. **Initialization**: Reads configuration and starts TCP listener on port 25565
2. **Monitoring Loop**: 
   - Checks all servers every 0.5 seconds
   - Displays real-time status (green=ok, red=down)
   - Monitors current active server
3. **Failover Logic**:
   - When current server fails, sends "next" message to other instances
   - Collects votes from other watchdog instances
   - Updates DNS when vote threshold is met (currently >2 votes)
4. **DNS Update**: Uses `nsupdate` to change A record to next available server

## Display

The script shows a live dashboard:

```
-----------------------------------------------
test.example.com -> 172.16.0.3
DNS_SERVER: 127.0.0.1
ping_timeout: 1
-----------------------------------------------

   IP               ping    https
172.16.0.3          ok      ok
1.1.1.1            down     down
8.8.8.8             ok      ok
```

## Quorum Communication

- Listens on TCP port 25565 for votes from other instances
- Sends "next" messages to trigger failover voting
- Prevents split-brain scenarios in multi-instance deployments

## Monitoring Methods

Choose monitoring method in config:

- **ping**: ICMP ping check (default)
- **https**: HTTPS connectivity test  
- **port**: TCP port connectivity check

## Planned Features

- ✅ Basic server monitoring and DNS failover
- ✅ Quorum-based decision making
- 🚧 **Coming Next**: Voting mechanism to return to higher priority servers
- 🔄 Configurable vote thresholds
- 📊 Health check scoring system

## Troubleshooting

**Script won't start**:
- Check if `socat` is installed
- Verify port 25565 is not in use: `netstat -tlnp | grep 25565`

**DNS updates failing**:
- Verify `nsupdate` has permissions to update the DNS zone
- Check DNS server configuration and zone settings

**Orphaned socat processes**:
- If script exits improperly: `pkill socat`
- Always use Ctrl+C to exit, not Ctrl+Z

## License

This script is provided as-is for educational and operational use.
