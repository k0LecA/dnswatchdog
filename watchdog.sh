#!/bin/bash

#v1.0

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
declare -a wdips=()
ip_count=0
declare -a messages=()
pointer=0
request_sent=1
new_ip_sent=1
#got_propose=1
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

    row=$((7+ip_count))
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
    
    for cmd in "${!packages[@]}"
    do
        if ! command -v "$cmd" &> /dev/null
        then
            missing+=("${packages[$cmd]}")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]
    then
        echo "Error: Missing dependencies ${missing[*]}. Install with:"
        echo "apt-get install ${missing[*]}"
        log "error" "Missing dependencies ${missing[*]}. Quiting"
        exit 1
    fi
}

read_config(){
    if [[ -f "$CONFIG_FILE" ]]
    then
        # shellcheck disable=SC1090
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
    method=${method:-"ping"}
    ping_count=${ping_count:-1}
    ping_timeout=${ping_timeout:-2}
    curl_timeout=${curl_timeout:-3}
    port=${port:-80}
    #curl_timeout=2
    if [ ${#ips[@]} -eq 0 ]
    then
        ips=("172.16.0.3" "1.1.1.1" "8.8.8.8")
    fi
    ip_count=${#ips[@]}

    #quorum listening
    listen_port=${listen_port:-25565}
    majority_needed=$(( (${#wdips[@]} / 2) + 1 ))
    if [ ${#wdips[@]} -eq 0 ]
    then
        wdips=("172.16.0.3" "172.16.0.4")
    fi
}

check_server() {
    ip="$1"
    check_method="$2"
    
    case $check_method in
    ping)
        ping -c "$ping_count" -W "$ping_timeout" "$ip" > /dev/null 2>&1 && return 0
        ;;
    https)
        curl -s --max-time "$curl_timeout" "https://$ip" > /dev/null 2>&1 && return 0
        ;;
    port)
        nc -z -w "$curl_timeout" "$ip" "$port" > /dev/null 2>&1 && return 0
        ;;
    esac
    return 1
}

find_best_available_ip() {
    # Find the highest priority IP that's available
    for i in "${!ips[@]}"
    do
        if check_server "${ips[$i]}" "$method"
        then
            echo "$i"
            return 0
        fi
    done
    echo "-1"  # No IP available
}

monitor_servers(){
    current_ip="${ips[$pointer]}"
    
    # Display monitoring status
    for i in "${!ips[@]}"
    do
        ip="${ips[$i]}"
        row=$((7+i))
        
        tput cup $row 0
        if [ "$i" -eq "$pointer" ]
        then
            echo -n "* $ip"
        else
            echo -n "  $ip"
        fi
        
        tput cup $row 25
        if check_server "$ip" "$method"
        then
            echo -en "${GREEN}UP${RESET}${CLEAR_LINE}"
        else
            echo -en "${RED}DOWN${RESET}${CLEAR_LINE}"
        fi
    done

    # Check if we need to switch
    best_available_index=$(find_best_available_ip)  
    if [ "$best_available_index" -eq -1 ]; then
        log "error" "No servers are available!"
        return
    fi
    
    # If current server is down, initiate switch
    if ! check_server "$current_ip" "$method"
    then
        log "warning" "Current server $current_ip is down"
        if [ "$best_available_index" -ne "$pointer" ]
        then
            log "info" "Proposing switch to ${ips[$best_available_index]}"
            propose_ip "${ips[$best_available_index]}"
        fi
    # If a higher priority server becomes available, switch to it
    elif [ "$best_available_index" -lt "$pointer" ]; then
        log "info" "Higher priority server ${ips[$best_available_index]} is available"
        propose_ip "${ips[$best_available_index]}"
    fi
}

send_request(){
    message="$1"
    for i in "${!wdips[@]}"
    do
        wdip="${wdips[$i]}"
        if echo "$message" | socat - TCP:"$wdip":25565
        then
            #log "info" "Request sent to $wdip successfully"
            request_sent=0
            return 0
        else
            log "error" "Failed to send message to $wdip (connection refused or timeout)"
            return 1
        fi
    done
}

propose_ip(){
    NEW_IP=$1
    if send_request "set $NEW_IP"
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
        tput cup 1 23
        echo -ne "${CLEAR_LINE}${GREEN}$NEW_IP${RESET}"
    else
        log "error" "DNS update failed for $RECORD -> $NEW_IP"
        tput cup 1 23
        echo -ne "${CLEAR_LINE}${RED}$NEW_IP (FAILED)${RESET}"
    fi
}

decide(){
    if [ $votes -gt 0 ]
    then
        ((pointer++))
        update_dns "${ips[$pointer]}"
        votes=0
    fi
    if [ $set_votes -gt 0 ]
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
            
            if [ "$line" = "next" ]
            then
                ((votes++))
                log "info" "Got a vote to change to next ip. Votes: $votes"
            else
                set -- $line
                if [ "$1" == "set" ]
                then
                    if [ "$2" == "ok" ]
                    then
                        ((set_votes++))
                        log "info" "Got a set_vote. Set_votes: $set_votes"
                    else
                        if [ "$3" == "force" ]
                        then
                            update_dns "$2"
                            log "warning" "forced to $2"
                            break
                        else
                            log "info" "Got a proposal for $2"
                            if check_server "$2" "ping"
                            then
                                log "info" "$2 is up"
                                #got_propose=0
                                proposed_ip="$2"
                                set_votes=0
                                send_request "set ok"
                            fi
                        fi
                    fi
                else
                    log "warning" "Unknown command: $1"
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
    echo "==============================================="
    echo "DNS Watchdog - Active: ${ips[$pointer]}"
    echo "DNS Server: $DNS_SERVER | Zone: $ZONE"
    echo "Record: $RECORD"
    echo "Method: $method | Quorum: $majority_needed/${#wdips[@]}"
    echo "==============================================="
    echo "Votes: next=$votes, propose=$set_votes (need $majority_needed)"
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