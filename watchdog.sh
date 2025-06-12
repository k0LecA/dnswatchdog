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
        row=$((1+i))
        tput cup $row 0
        echo -n "$ip"
        tput cup $row 22

        if check_server "$ip" "ping"
        then
            echo -en "${GREEN}ok${RESET}${CLEAR_LINE}"
        else
            echo -en "${RED}down${RESET}${CLEAR_LINE}"
        fi




    done
}

read_config

clear
#     row  column
tput cup 0 3
echo -n "IP"
tput cup 0 20
echo -n "Status"
echo
while true
do
    #clear
    monitor_servers
    #echo $pointer
    sleep 1
done