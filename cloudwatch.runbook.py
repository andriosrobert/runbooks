#!/bin/bash
# CloudWatch Logs – Relative Window Fetcher (Bash Version)
# Author  : Andrios @ hoopdev
# Purpose : Pull events from a log group for a preset relative window
#           (5 m … 4 w), matching the AWS-console buttons
# Requires: aws-cli, jq

# ───────── UI parameters (no free-text numbers) ─────────
# Read log group from environment variable
log_group_name="${LOG_GROUP_NAME}"

if [ -z "$log_group_name" ]; then
    echo "❌ Error: LOG_GROUP_NAME environment variable is not set"
    echo "Usage: LOG_GROUP_NAME='/aws/containerinsights/hoop-prod/application' $0"
    exit 1
fi

relative_window='
{{ .relativeWindow | type "select"
                  | description "Time window duration"
                  | options "5m" "10m" "15m" "30m" "45m"
                            "1h" "2h" "3h" "6h" "8h" "12h"
                            "1d" "2d" "3d" "4d" "5d" "6d"
                            "1w" "2w" "3w" "4w"
                  | default "5m" }}
'
relative_window=$(echo "$relative_window" | xargs)

specific_month='
{{ .specificMonth | type "select"
                  | description "Month (optional - leave as current for relative mode)"
                  | options "current" "January" "February" "March" "April" "May" "June"
                            "July" "August" "September" "October" "November" "December"
                  | default "current" }}
'
specific_month=$(echo "$specific_month" | xargs)

specific_day='
{{ .specificDay | type "select"
                | description "Day of month (optional - use with month selection)"
                | options "current" "1" "2" "3" "4" "5" "6" "7" "8" "9" "10"
                          "11" "12" "13" "14" "15" "16" "17" "18" "19" "20"
                          "21" "22" "23" "24" "25" "26" "27" "28" "29" "30" "31"
                | default "current" }}
'
specific_day=$(echo "$specific_day" | xargs)

# ────────────────────────────────────────────────────────

# Allow environment variable override for log group
if [ -n "$LOG_GROUP_NAME" ]; then
    log_group_name="$LOG_GROUP_NAME"
fi

# ───────── Color support (optional) ─────────
if [ -t 1 ] && command -v tput >/dev/null 2>&1; then
    DIM=$(tput dim)
    BOLD=$(tput bold)
    HEAD=$(tput setaf 6)  # cyan
    RESET=$(tput sgr0)
else
    DIM=""
    BOLD=""
    HEAD=""
    RESET=""
fi

# ───────── Helper functions ─────────
window_to_seconds() {
    local win=$1
    local num=$(echo "$win" | sed 's/[^0-9]//g')
    local unit=$(echo "$win" | sed 's/[0-9]//g')
    
    case $unit in
        m) echo $((num * 60)) ;;
        h) echo $((num * 3600)) ;;
        d) echo $((num * 86400)) ;;
        w) echo $((num * 604800)) ;;
        *) echo "❌ Unsupported window: $win" >&2; exit 1 ;;
    esac
}

month_to_number() {
    case $(echo "$1" | tr '[:upper:]' '[:lower:]') in
        january)   echo 1 ;;
        february)  echo 2 ;;
        march)     echo 3 ;;
        april)     echo 4 ;;
        may)       echo 5 ;;
        june)      echo 6 ;;
        july)      echo 7 ;;
        august)    echo 8 ;;
        september) echo 9 ;;
        october)   echo 10 ;;
        november)  echo 11 ;;
        december)  echo 12 ;;
        *)         echo 0 ;;
    esac
}

extract_message() {
    local raw="$1"
    # Try to extract log/message/msg field from JSON
    if [[ "$raw" =~ ^\{.*\}$ ]]; then
        # Try to extract common log fields
        local extracted
        for field in log message msg; do
            extracted=$(echo "$raw" | jq -r ".$field // empty" 2>/dev/null)
            if [ -n "$extracted" ]; then
                echo "$extracted"
                return
            fi
        done
        # If no field found, truncate the raw JSON
        echo "$raw" | cut -c1-120
    else
        echo "$raw"
    fi
}

# ─────────── Main logic ─────────
main() {
    # Calculate time window
    local now_ms=$(($(date +%s) * 1000))
    local window_seconds=$(window_to_seconds "$relative_window")
    local window_desc end_ms start_ms
    
    # Determine if using specific date
    if [ "$specific_month" != "current" ] || [ "$specific_day" != "current" ]; then
        # Specific date mode
        local year=$(date +%Y)
        local month day
        
        if [ "$specific_month" != "current" ]; then
            month=$(month_to_number "$specific_month")
        else
            month=$(date +%-m)
        fi
        
        if [ "$specific_day" != "current" ]; then
            day=$specific_day
        else
            day=$(date +%-d)
        fi
        
        # Create end date timestamp (end of day)
        local end_date="$year-$(printf %02d $month)-$(printf %02d $day) 23:59:59"
        end_ms=$(date -d "$end_date" +%s000 2>/dev/null || date -j -f "%Y-%m-%d %H:%M:%S" "$end_date" +%s000 2>/dev/null)
        
        # Cap at current time if future
        if [ $end_ms -gt $now_ms ]; then
            end_ms=$now_ms
        fi
        
        window_desc="$relative_window window on $(date -d @$((end_ms/1000)) +%Y-%m-%d 2>/dev/null || date -r $((end_ms/1000)) +%Y-%m-%d)"
    else
        # Relative mode
        end_ms=$now_ms
        window_desc="last $relative_window"
    fi
    
    start_ms=$((end_ms - (window_seconds * 1000)))
    
    # Display header
    echo "⏱️  Window : $window_desc  ($(date -u -d @$((start_ms/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u -r $((start_ms/1000)) '+%Y-%m-%d %H:%M:%S')Z → $(date -u -d @$((end_ms/1000)) '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date -u -r $((end_ms/1000)) '+%Y-%m-%d %H:%M:%S')Z)"
    echo "📒 Group  : $log_group_name"
    echo "🔍 Pattern: (none)"
    echo
    
    # Fetch events
    local events_file=$(mktemp)
    local next_token=""
    local total_events=0
    
    while true; do
        local cmd="aws logs filter-log-events --log-group-name '$log_group_name' --start-time $start_ms --end-time $end_ms"
        
        if [ -n "$next_token" ]; then
            cmd="$cmd --next-token '$next_token'"
        fi
        
        local response=$(eval $cmd 2>/dev/null)
        
        if [ $? -ne 0 ]; then
            echo "❌ Error fetching logs. Check your AWS credentials and log group name."
            rm -f "$events_file"
            exit 1
        fi
        
        # Extract events and append to file
        echo "$response" | jq -r '.events[] | @json' >> "$events_file"
        
        # Count events
        local batch_count=$(echo "$response" | jq -r '.events | length')
        total_events=$((total_events + batch_count))
        
        # Get next token
        next_token=$(echo "$response" | jq -r '.nextToken // empty')
        
        if [ -z "$next_token" ]; then
            break
        fi
    done
    
    echo "✅ $total_events event(s) retrieved"
    echo
    
    # Display table header
    printf "${HEAD}%-24s %-24s Message${RESET}\n" "Event time" "Ingestion"
    
    # Process and display events
    while IFS= read -r event_json; do
        local event=$(echo "$event_json" | jq -r '.')
        
        # Extract timestamps
        local timestamp=$(echo "$event" | jq -r '.timestamp')
        local ingestion_time=$(echo "$event" | jq -r '.ingestionTime // empty')
        local message=$(echo "$event" | jq -r '.message')
        
        # Format timestamps
        local event_time=$(date -u -d @$((timestamp/1000)) '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null || date -u -r $((timestamp/1000)) '+%Y-%m-%dT%H:%M:%S.000Z')
        local ing_time=""
        if [ -n "$ingestion_time" ]; then
            ing_time=$(date -u -d @$((ingestion_time/1000)) '+%Y-%m-%dT%H:%M:%S.%3NZ' 2>/dev/null || date -u -r $((ingestion_time/1000)) '+%Y-%m-%dT%H:%M:%S.000Z')
        fi
        
        # Extract message content
        local display_msg=$(extract_message "$message")
        
        # Display row
        printf "${DIM}%-24s %-24s${RESET} ${BOLD}%s${RESET}\n" "$event_time" "$ing_time" "$display_msg"
        
    done < "$events_file"
    
    # Cleanup
    rm -f "$events_file"
}

# ─────────── Entry point ─────────
main
