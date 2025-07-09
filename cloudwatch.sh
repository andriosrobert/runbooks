#!/usr/bin/env bash
#
# CloudWatch Logs – Relative Window Fetcher (Shell Version)
# Author  : Andrios @ hoopdev
# Purpose : Pull events from a log group for a preset relative window
#           (5 m … 4 w), matching the AWS-console buttons
# Requires: aws-cli, jq

set -euo pipefail

# ───────── UI parameters (no free-text numbers) ─────────
# {{ .logGroupName | type "select" | description "Choose CloudWatch log group" | options "/aws/containerinsights/hoop-prod/application" "/aws/containerinsights/hoop-prod/dataplane" "/aws/eks/hoop-prod/cluster" "/aws/lambda/logdna_cloudwatch" "/aws/rds/instance/hoopdb/postgresql" | asenv "LOG_GROUP_NAME" }}
# {{ .relativeWindow | type "select" | description "Time window duration" | options "5m" "10m" "15m" "30m" "45m" "1h" "2h" "3h" "6h" "8h" "12h" "1d" "2d" "3d" "4d" "5d" "6d" "1w" "2w" "3w" "4w" | default "5m" | asenv "RELATIVE_WINDOW" }}
# {{ .specificMonth | type "select" | description "Month (optional - leave as 'current' for relative mode)" | options "current" "January" "February" "March" "April" "May" "June" "July" "August" "September" "October" "November" "December" | default "current" | asenv "SPECIFIC_MONTH" }}
# {{ .specificDay | type "select" | description "Day of month (optional - use with month selection)" | options "current" "1" "2" "3" "4" "5" "6" "7" "8" "9" "10" "11" "12" "13" "14" "15" "16" "17" "18" "19" "20" "21" "22" "23" "24" "25" "26" "27" "28" "29" "30" "31" | default "current" | asenv "SPECIFIC_DAY" }}

# Get values from environment variables (with defaults for local testing)
LOG_GROUP_NAME="${LOG_GROUP_NAME:-/aws/containerinsights/hoop-prod/application}"
RELATIVE_WINDOW="${RELATIVE_WINDOW:-5m}"
SPECIFIC_MONTH="${SPECIFIC_MONTH:-current}"
SPECIFIC_DAY="${SPECIFIC_DAY:-current}"

# ───────── Color support (optional) ─────────
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    DIM=$(tput dim 2>/dev/null || echo "")
    BOLD=$(tput bold 2>/dev/null || echo "")
    CYAN=$(tput setaf 6 2>/dev/null || echo "")
    RESET=$(tput sgr0 2>/dev/null || echo "")
else
    DIM=""
    BOLD=""
    CYAN=""
    RESET=""
fi

# ───────────────────────── helpers ────────────────────────────
window_to_seconds() {
    local win="$1"
    local num="${win%[mhdw]}"
    local unit="${win#${num}}"
    
    case "$unit" in
        m) echo $((num * 60)) ;;
        h) echo $((num * 3600)) ;;
        d) echo $((num * 86400)) ;;
        w) echo $((num * 604800)) ;;
        *) echo "❌ Unsupported window: $win" >&2; exit 1 ;;
    esac
}

month_to_number() {
    local month="${1,,}"  # lowercase
    case "$month" in
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

format_timestamp() {
    local ts_ms="$1"
    local ts_sec=$((ts_ms / 1000))
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS date command
        date -u -r "$ts_sec" "+%Y-%m-%dT%H:%M:%S.${ts_ms: -3}Z"
    else
        # GNU date command
        date -u -d "@$ts_sec" "+%Y-%m-%dT%H:%M:%S.${ts_ms: -3}Z"
    fi
}

extract_message() {
    local raw="$1"
    # Try to extract message from JSON, otherwise return as-is
    if [[ "$raw" =~ ^\{.*\}$ ]]; then
        # Try to extract log/message/msg field from JSON
        local extracted
        extracted=$(echo "$raw" | jq -r '.log // .message // .msg // empty' 2>/dev/null)
        if [[ -n "$extracted" ]]; then
            echo "$extracted"
        else
            # If JSON parsing fails or no message field, truncate if too long
            if [[ ${#raw} -gt 120 ]]; then
                echo "${raw:0:117} …"
            else
                echo "$raw"
            fi
        fi
    else
        echo "$raw"
    fi
}

# ─────────────────────────  main  ─────────────────────────────
main() {
    # Check dependencies
    if ! command -v aws >/dev/null 2>&1; then
        echo "❌ Error: aws-cli is required but not installed." >&2
        exit 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        echo "❌ Error: jq is required but not installed." >&2
        exit 1
    fi

    # Calculate timestamps
    local now_ms=$(($(date +%s) * 1000))
    local window_seconds=$(window_to_seconds "$RELATIVE_WINDOW")
    local window_desc end_ms start_ms

    # Determine if we're using specific date or relative mode
    if [[ "$SPECIFIC_MONTH" != "current" || "$SPECIFIC_DAY" != "current" ]]; then
        # Specific date mode
        local year=$(date +%Y)
        local month day
        
        if [[ "$SPECIFIC_MONTH" != "current" ]]; then
            month=$(month_to_number "$SPECIFIC_MONTH")
        else
            month=$(date +%m)
        fi
        
        if [[ "$SPECIFIC_DAY" != "current" ]]; then
            day="$SPECIFIC_DAY"
        else
            day=$(date +%d)
        fi
        
        # Create end timestamp (end of specified day)
        local end_date="${year}-$(printf "%02d" "$month")-$(printf "%02d" "$day") 23:59:59"
        if [[ "$OSTYPE" == "darwin"* ]]; then
            end_ms=$(($(date -u -j -f "%Y-%m-%d %H:%M:%S" "$end_date" +%s) * 1000))
        else
            end_ms=$(($(date -u -d "$end_date" +%s) * 1000))
        fi
        
        # Cap at current time if future date
        if [[ $end_ms -gt $now_ms ]]; then
            end_ms=$now_ms
        fi
        
        start_ms=$((end_ms - (window_seconds * 1000)))
        window_desc="${RELATIVE_WINDOW} window on ${year}-$(printf "%02d" "$month")-$(printf "%02d" "$day")"
    else
        # Relative mode
        end_ms=$now_ms
        start_ms=$((end_ms - (window_seconds * 1000)))
        window_desc="last ${RELATIVE_WINDOW}"
    fi

    # Display query info
    echo "⏱️  Window : ${window_desc}  ($(format_timestamp "$start_ms") → $(format_timestamp "$end_ms"))"
    echo "📒 Group  : ${LOG_GROUP_NAME}"
    echo "🔍 Pattern: (none)"
    echo

    # Fetch events
    local events_file=$(mktemp)
    trap "rm -f $events_file" EXIT

    local next_token=""
    local total_events=0

    while true; do
        local aws_cmd=(aws logs filter-log-events
            --log-group-name "$LOG_GROUP_NAME"
            --start-time "$start_ms"
            --end-time "$end_ms"
            --output json)
        
        if [[ -n "$next_token" ]]; then
            aws_cmd+=(--next-token "$next_token")
        fi

        local response
        response=$("${aws_cmd[@]}" 2>&1) || {
            echo "❌ Error querying CloudWatch: $response" >&2
            exit 1
        }

        # Append events to file
        echo "$response" | jq -r '.events[]' >> "$events_file"
        total_events=$(wc -l < "$events_file" | tr -d ' ')

        # Check for next token
        next_token=$(echo "$response" | jq -r '.nextToken // empty')
        [[ -z "$next_token" ]] && break
    done

    echo "✅ ${total_events} event(s) retrieved"
    echo

    # Display table header
    printf "${CYAN}%-24s %-24s Message${RESET}\n" "Event time" "Ingestion"

    # Process and display events
    while IFS= read -r event; do
        local timestamp=$(echo "$event" | jq -r '.timestamp')
        local ingestion_time=$(echo "$event" | jq -r '.ingestionTime // empty')
        local message=$(echo "$event" | jq -r '.message')

        local event_time=$(format_timestamp "$timestamp")
        local ing_time=""
        if [[ -n "$ingestion_time" ]]; then
            ing_time=$(format_timestamp "$ingestion_time")
        fi

        local extracted_msg=$(extract_message "$message")

        printf "${DIM}%-24s %-24s${RESET} ${BOLD}%s${RESET}\n" \
            "$event_time" "$ing_time" "$extracted_msg"
    done < "$events_file"
}

# Run main function
main "$@"
