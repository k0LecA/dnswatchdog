#!/bin/bash

#COLORS
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
RESET='\e[0m'
CLEAR_LINE='\e[K'

#FILES
CONFIG_FILE="./watchdog.cfg"
LOG_FILE="/var/log/watchdog.log"
LISTENER_MESSAGES=$(mktemp)

#GLOBAL VARIABLES
declare -a ips=()
ip_count=0
declare -a messages=()
pointer=0
request_sent=1
votes=0
listener_pid=0

log(){
    type="$1"
    message="$2"
    case $type in
    info)
        echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] INFO - ${message}" >> "$LOG_FILE"
    ;;
    warning)
        echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${YELLOW}WARNING${RESET} - ${message}" >> "$LOG_FILE"
    ;;
    error)
        echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}ERROR${RESET} - ${message}" >> "$LOG_FILE"
    ;;
    esac

    row=$((6+ip_count))
    tput cup $row 1
    echo "-----------------------------------------------"
    echo "Last logs:"
    tail $LOG_FILE
}

check_dependencies() {
    local missing=()
    declare -A packages=(
        ["socat"]="socat"
        ["ping"]="iputils-ping"
        ["curl"]="curl" 
        ["nc"]="netcat-openbsd"
        ["nsupdate"]="bind9-utils"
        ["tput"]="ncurses-bin"
    )
    
    for cmd in "${!packages[@]}"; do
        if ! command -v "$cmd" &> /dev/null; then
            missing+=("${packages[$cmd]}")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        echo "Error: Missing dependencies ${missing[*]}. Install with:"
        echo "apt-get install ${missing[*]}"
        log "error" "Missing dependencies ${missing[*]}. Quiting"
        exit 1
    fi
}

read_config(){
   if [[ -f "$CONFIG_FILE" ]]; then
       source "$CONFIG_FILE"
       log "info" "Using configuration from $CONFIG_FILE"
   else
       log "warning" "Configuration file $CONFIG_FILE not found, using defaults"
   fi

   #DNS
   DNS_SERVER=${DNS_SERVER:-127.0.0.1}
   ZONE=${ZONE:-"example.com"}
   RECORD=${RECORD:-"test.example.com"}

   #monitoring
   method="ping"
   ping_count=${ping_count:-1}
   ping_timeout=${ping_timeout:-1}

   #method="https"
   #curl_timeout=2

   #method="port"
   #port=80

   #quorum listening
   listen_port=${listen_port:-25565}

   #ip list
   #sort by priority from highest to lowest
   if [ ${#ips[@]} -eq 0 ]; then
       ips=("172.16.0.3" "1.1.1.1" "8.8.8.8")
   fi
   ip_count=${#ips[@]}
}

check_server() {
    ip="$1"
    method="$2"
    case $method in
    ping)
      ping -c 1 -W 1 "$ip" > /dev/null 2>&1 && return 0
      ;;
    https)
      curl -s --max-time 2 "https://$ip" > /dev/null && return 0
      ;;
    port)
      nc -z -w 2 "$ip" 80 && return 0
      ;;
  esac

  return 1
}


monitor_servers(){
    #monitor all servers
    for i in "${!ips[@]}"
    do
        ip="${ips[$i]}"

        row=$((6+i))
        tput cup $row 0
        echo -n "$ip"
        
        tput cup $row 21
        if check_server "$ip" "ping"
        then
            echo -en "${GREEN}ok${RESET}${CLEAR_LINE}"
            #if [ $i -le $pointer ]
            #then
            #    echo
            #fi
        else
            echo -en "${RED}down${RESET}${CLEAR_LINE}"
        fi

        tput cup $row 32
        if check_server "$ip" "https"
        then
            echo -en "${GREEN}ok${RESET}${CLEAR_LINE}"
        else
            echo -en "${RED}down${RESET}${CLEAR_LINE}"
        fi
    done

    #check current ip
    #check if request was sent
    if [ $request_sent -eq 1 ]
    then
        #if request was sent check if current server is accessible
        if ! check_server ${ips[$pointer]} "ping"
        then

            send_request
        fi
    fi
}

send_request(){
    echo "next" | socat - TCP:172.16.0.3:25565
    request_sent=0
}

update_dns(){
    NEW_IP=${ips[$pointer]}
    
    if nsupdate <<EOF
server $DNS_SERVER
zone $ZONE
update delete $RECORD A
update add $RECORD 60 A $NEW_IP
send
EOF
    then
        log "info" "DNS updated: $RECORD -> $NEW_IP"
        tput cup 1 20
        echo -ne "${CLEAR_LINE}${GREEN}${ips[$pointer]}${RESET}"
    else
        log "error" "DNS update failed for $RECORD -> $NEW_IP"
        tput cup 1 20
        echo -ne "${CLEAR_LINE}${RED}${ips[$pointer]} (FAILED)${RESET}"
    fi
}

decide(){
    if [ $votes -gt 2 ]
    then
        ((pointer++))
        update_dns
        votes=0
    fi
}

start_listener()
{
    socat TCP-LISTEN:25565,fork SYSTEM:"while read line; do echo \"\$line\" >> $LISTENER_MESSAGES; done" &
    listener_pid=$!
}

listen(){
    if [ -f "$LISTENER_MESSAGES" ]; then
        while IFS= read -r line; do
            messages+=("$line")
            if [ "$line" = "next" ]
            then
                ((votes++))
                tput cup 14 0
                echo -ne "${CLEAR_LINE}votes: "$votes
            fi
        done < "$LISTENER_MESSAGES"
        > "$LISTENER_MESSAGES"  # clear the file after reading
    fi
}

stop_listener()
{
    if [ $listener_pid -ne 0 ]; then
        kill $listener_pid 2>/dev/null
        listener_pid=0
        echo "Listener stopped"
    fi
}

cleanup()
{
    stop_listener
    rm -f "$LISTENER_MESSAGES"
    log "info" "Stopping dns watchdog"
    exit 0
}

update_header(){
    clear
    echo "-----------------------------------------------"
    echo "test.example.com -> "${ips[$pointer]}
    echo "DNS_SERVER: "$DNS_SERVER
    echo "ping_timeout: " $ping_timeout
    echo "-----------------------------------------------"

    #     row  column
    tput cup 5 3
    echo -n "IP"
    tput cup 5 20
    echo -n "ping"
    tput cup 5 30
    echo -n "https"
    echo

}

main(){
    trap cleanup SIGINT SIGTERM EXIT #proper exit with CTRL+C
    
    log info "Starting dns watchdog"
    read_config
    update_header
    check_dependencies

    start_listener #start listening with socat, will be added quorum

    while true
    do
        listen
        decide
        monitor_servers 
        sleep 0.5
    done
}

main "$@"