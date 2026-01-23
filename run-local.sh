#!/bin/bash

# Local development runner with log files
# Logs are written to /tmp/*.log for easy access

LOG_DIR="/tmp"
FLOW_DIR="/Users/tupham/dev/flow"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting Flow services with logging...${NC}"
echo -e "Log files will be in: ${YELLOW}$LOG_DIR${NC}"
echo ""

# Function to start a service
start_service() {
    local name=$1
    local dir=$2
    local cmd=$3
    local log_file="$LOG_DIR/$name.log"

    echo -e "${GREEN}Starting $name...${NC}"
    echo -e "  Dir: $dir"
    echo -e "  Log: ${YELLOW}$log_file${NC}"

    # Clear old log
    > "$log_file"

    # Start service in background with logging
    cd "$dir" && $cmd > "$log_file" 2>&1 &
    echo $! > "$LOG_DIR/$name.pid"
    echo -e "  PID: $(cat $LOG_DIR/$name.pid)"
    echo ""
}

# Stop all services
stop_all() {
    echo -e "${RED}Stopping all services...${NC}"
    for pid_file in $LOG_DIR/*.pid; do
        if [ -f "$pid_file" ]; then
            pid=$(cat "$pid_file")
            name=$(basename "$pid_file" .pid)
            if kill -0 "$pid" 2>/dev/null; then
                echo "Stopping $name (PID: $pid)"
                kill "$pid" 2>/dev/null
            fi
            rm -f "$pid_file"
        fi
    done
    echo "Done."
}

# Handle Ctrl+C
trap stop_all EXIT

case "$1" in
    stop)
        stop_all
        exit 0
        ;;
    logs)
        # Tail all logs
        tail -f $LOG_DIR/shared.log $LOG_DIR/tasks.log $LOG_DIR/projects.log $LOG_DIR/frontend.log
        ;;
    *)
        # Start all services
        start_service "shared" "$FLOW_DIR/backend/shared" "go run cmd/main.go"
        start_service "tasks" "$FLOW_DIR/backend/tasks" "go run cmd/main.go"
        start_service "projects" "$FLOW_DIR/backend/projects" "go run cmd/main.go"
        start_service "frontend" "$FLOW_DIR/apps/flow_tasks" "flutter run -d chrome --web-port=3000"

        echo -e "${GREEN}All services started!${NC}"
        echo ""
        echo "Commands:"
        echo "  View logs:  tail -f /tmp/*.log"
        echo "  Tasks log:  tail -f /tmp/tasks.log"
        echo "  Stop all:   ./run-local.sh stop"
        echo ""
        echo "Press Ctrl+C to stop all services..."

        # Wait for Ctrl+C
        wait
        ;;
esac
