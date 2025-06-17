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
new_ip_sent=1
got_propose=1
proposed_ip=""
votes=0
set_votes=0
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
    tput cup $row 0
    tput ed
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
            if [ $i -lt $pointer ]
            then
                if [ $new_ip_sent -eq 1 ]
                then
                    propose_ip "$ip"
                fi
            fi
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
    if [ $new_ip_sent -eq 1 ]
    then
        if [ $request_sent -eq 1 ]
        then
            #if request was sent check if current server is accessible
            if ! check_server ${ips[$pointer]} "ping"
            then
                log "warning" "${ips[$pointer]} not responding, sending request to change."
                send_request
            fi
        fi
    fi
}

send_request(){
    if echo "next" | socat - TCP:172.16.0.3:25565
    then
        log "info" "Request sent successfully"
        request_sent=0
    else
        log "error" "Failed to send message (connection refused or timeout)"
    fi
}

propose_ip(){
    NEW_IP=$1
    if echo "set ${NEW_IP}" | socat - TCP:172.16.0.3:25565
    then
        log "info" "Suggested ${NEW_IP} sent successfully"
        new_ip_sent=0
        proposed_ip="$NEW_IP"
    else
        log "error" "Failed to propose ${NEW_IP} (connection refused or timeout)"
    fi
}

update_dns(){
    NEW_IP=$1
    
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
    if [ $votes -gt 1 ]
    then
        ((pointer++))
        update_dns "${ips[$pointer]}"
        votes=0
    fi
    if [ $set_votes -gt 1 ]
    then
        for i in "${!ips[@]}"
        do
            if [[ "${ips[$i]}" == "$proposed_ip" ]]; then
            pointer=$i
            break
            fi
        done
        update_dns "$proposed_ip"
        set_votes=0
    fi
}

start_listener()
{
    if socat TCP-LISTEN:25565,fork SYSTEM:"while read line; do echo \"\$line\" >> $LISTENER_MESSAGES; done" &
    then
        listener_pid=$!
        log "info" "Listener started successfully :)"
    else
        log "error" "Listener failed to start."
    fi

}

listen(){
    if [ -f "$LISTENER_MESSAGES" ]; then
        while IFS= read -r line; do
            messages+=("$line")
            
            if [ $line = "next" ]
            then
                ((votes++))
                log "info" "Got a vote to change to next ip. Votes: $votes"
            else
                set -- $line
                if [ $1 == "set" ]
                then
                    if [ $2 == "ok" ]
                    then
                        ((set_votes++))
                        log "info" "Got a set_vote. Set_votes: $set_votes"
                    else
                        log "info" "Got a proposal for $2"
                        if check_server "$2" "ping"
                        then
                            log "info" "$2 is up"
                            new_ip_sent=1
                            got_propose=0
                            proposed_ip="$2"
                            set_votes=0
                            echo "set ok" | socat - TCP:172.16.0.3:25565
                        fi
                    fi
                fi
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
        log "info" "Listener stopped"
    fi
}

cleanup()
{
    stop_listener
    rm -f "$LISTENER_MESSAGES"
    log "info" "Stopping dns watchdog"
    tput cnorm
    exit 0
}

update_header(){
    tput civis
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