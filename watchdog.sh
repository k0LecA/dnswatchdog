#!/bin/bash

#COLORS
RED='\e[31m'
GREEN='\e[32m'
YELLOW='\e[33m'
RESET='\e[0m'
CLEAR_LINE='\e[K'

#CONFIGS
config="./config"

#GLOBAL VARIABLES
declare -a ips=()
pointer=0
DNS_SERVER="127.0.0.1"
ZONE="example.com"
RECORD="test.example.com"

read_config(){
    while read -r line
    do
        ips+=("$line")
    done < "$config"
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
    for i in "${!ips[@]}"
    do
        ip="${ips[$i]}"


        #if ping -c 1 -W 1 $ip > /dev/null 2>&1;
        row=$((4+i))
        tput cup $row 0
        echo -n "$ip"
        
        tput cup $row 21
        if check_server "$ip" "ping"
        then
            echo -en "${GREEN}ok${RESET}${CLEAR_LINE}"
            if [ $i -le $pointer ]
            then
                pointer=$i
                update_dns
            fi
        else
            echo -en "${RED}down${RESET}${CLEAR_LINE}"
            if [ $pointer -eq $i ]
            then
                pointer+=1
                update_dns
            fi
        fi

        tput cup $row 32
        if check_server "$ip" "https"
        then
            echo -en "${GREEN}ok${RESET}${CLEAR_LINE}"
        else
            echo -en "${RED}down${RESET}${CLEAR_LINE}"
        fi


    done
}

update_dns(){
    NEW_IP=${ips[$pointer]}
    nsupdate <<EOF
server $DNS_SERVER
zone $ZONE
update delete $RECORD A
update add $RECORD 60 A $NEW_IP
send
EOF

    tput cup 1 21
    echo -ne "${ips[$pointer]}${CLEAR_LINE}"
}

start_listener()
{
    socat TCP-LISTEN:25565,fork SYSTEM:'while read line; do echo "$line" >> /tmp/listener_messages; done' &
listener_pid=$!
}

listen(){
    if [ -f /tmp/listener_messages ]; then
        while IFS= read -r line; do
            messages+=("$line")
        done < /tmp/listener_messages
        #> /tmp/listener_messages  # clear the file after reading
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
    rm -f /tmp/listener_messages
    exit 0
}

update_header(){
    clear
    echo "-----------------------------------------------"
    echo "test.example.com -> "
    echo "-----------------------------------------------"

    #     row  column
    tput cup 3 3
    echo -n "IP"
    tput cup 3 20
    echo -n "ping"
    tput cup 3 30
    echo -n "https"
    echo

}

main(){
    trap cleanup SIGINT SIGTERM EXIT
#set -- $input panaudoti "192.168.0.0  1  1  0  1"
#                          $1         $2 $3 $4 $5
    read_config
    start_listener
    update_header
    while true
    do
        listen
        monitor_servers
        sleep 1
    done
}

main "$@"