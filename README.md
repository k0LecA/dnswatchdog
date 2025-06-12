# dnswatchdog
# Server Monitor & DNS Failover Script

A bash script that monitors multiple servers and automatically updates DNS records to provide failover functionality. The script continuously monitors server availability using ping and HTTPS checks, and automatically switches DNS records to healthy servers when failures are detected.

## Features

- **Multi-server monitoring**: Monitor multiple servers simultaneously
- **Dual health checks**: Uses both ping and HTTPS connectivity tests
- **Automatic DNS failover**: Updates DNS records via nsupdate when servers fail
- **Real-time display**: Live terminal interface showing server status
- **Color-coded output**: Visual indicators for server health status
- **Configurable**: Server list managed through external config file

## Prerequisites

- `bash` shell
- `ping` command
- `curl` for HTTPS checks
- `nc` (netcat) for port checking
- `nsupdate` for DNS updates
- DNS server that accepts dynamic updates

## Installation

1. Clone or download the script
2. Make it executable:
   ```bash
   chmod +x monitor.sh
   ```
3. Create a config file with your server IPs (see Configuration section)

## Configuration

### Config File
Create a `config` file in the same directory as the script. List one IP address per line:

```
192.168.1.10
192.168.1.11
192.168.1.12
10.0.0.5
```

### Script Variables
Edit the following variables in the script to match your environment:

```bash
DNS_SERVER="127.0.0.1"        # Your DNS server IP
ZONE="example.com"            # Your DNS zone
RECORD="test.example.com"     # The DNS record to update
```

## Usage

Run the script:
```bash
./monitor.sh
```

The script will:
1. Load server IPs from the config file
2. Display a real-time monitoring interface
3. Continuously check server health
4. Automatically update DNS records when failures occur

### Display Interface

```
-----------------------------------------------
test.example.com -> 192.168.1.10
-----------------------------------------------
   IP                  ping     https
192.168.1.10          ok       ok
192.168.1.11          down     down
192.168.1.12          ok       ok
```

## Health Check Methods

The script supports three health check methods:

1. **ping**: ICMP ping test (1 second timeout)
2. **https**: HTTPS connectivity test (2 second timeout)
3. **port**: TCP port 80 connectivity test (2 second timeout)

Currently, the monitoring loop uses ping and HTTPS checks.

## DNS Failover Logic

- Servers are prioritized by their order in the config file
- The script maintains a pointer to the current active server
- When the active server fails, it switches to the next available healthy server
- When a higher-priority server comes back online, it switches back
- DNS updates are performed using nsupdate with a 60-second TTL

## DNS Server Requirements

Your DNS server must:
- Accept dynamic updates via nsupdate
- Be properly configured with the appropriate zone
- Allow updates from the machine running this script

For BIND9, you might need to configure update policies in your zone configuration.

## Customization

### Adding New Health Check Methods
You can extend the `check_server()` function to add new monitoring methods:

```bash
check_server() {
  ip="$1"
  method="$2"
  case $method in
    # ... existing methods ...
    http)
      curl -s --max-time 2 "http://$ip" > /dev/null && return 0
      ;;
  esac
  return 1
}
```

### Modifying Check Intervals
Change the sleep duration in the main loop:
```bash
sleep 5  # Check every 5 seconds instead of 1
```

## Troubleshooting

### Common Issues

1. **Permission denied for nsupdate**
   - Ensure your DNS server allows dynamic updates
   - Check TSIG keys if authentication is required

2. **Config file not found**
   - Ensure the `config` file exists in the script directory
   - Check file permissions

3. **Commands not found**
   - Install required tools: `curl`, `nc`, `bind-utils` (for nsupdate)

### Debug Mode
Add `set -x` at the beginning of the script to enable debug output.

## Security Considerations

- The script performs DNS updates without authentication by default
- Consider implementing TSIG authentication for production use
- Ensure proper firewall rules for DNS update traffic
- Run with minimal required privileges

## License

This script is provided as-is for educational and operational purposes. Modify and distribute as needed.

## Contributing

Feel free to submit improvements, bug fixes, or additional features via pull requests.
