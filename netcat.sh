#!/bin/bash

# Minimal http server (resp 200 OK)

readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

#TODO: Adjust port
PORT=8080

echo -e "${CYAN}Server run on port $PORT${NC}"
echo 
trap "pkill -P $$; exit" INT TERM
while true; do echo -e "HTTP/1.1 200 OK\n\nOK" | nc -l -p $PORT -q 1; done
