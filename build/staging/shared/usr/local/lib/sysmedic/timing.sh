# SysMedic Timing Library — execution time logging for sysmedic-* tools
# Source this in any sysmedic tool: . /usr/local/lib/sysmedic/timing.sh
# Usage:
#   sysmedic_time_start "tool-name"
#   ... do work ...
#   sysmedic_time_end "tool-name" [extra-notes]

# Returns the session audit log path
_sysmedic_audit_file() {
    local d
    d=$(readlink -f /run/sysmedic/latest 2>/dev/null)
    if [ -n "$d" ] && [ -d "$d" ]; then echo "$d/audit.log"; else mkdir -p /run/sysmedic; echo /run/sysmedic/audit.log; fi
}

# Start timing a tool
# Usage: sysmedic_time_start "tool-name" [extra-context]
sysmedic_time_start() {
    local tool="${1:-unknown}"
    local ctx="${2:-}"
    local audit_file
    audit_file=$(_sysmedic_audit_file)

    # Store start time in a temp file keyed by tool name + PID
    local ts_file="/tmp/sysmedic-timing-${tool}-$$.ts"
    date +%s.%N > "$ts_file"

    # Log start
    local tty
    tty=$(tty 2>/dev/null | sed 's|/dev/||')
    [ -z "$tty" ] && tty="ai:${SYSMEDIC_AI:-script}"
    printf '%s [%s] TIMING start: %s %s\n' "$(date -Is)" "$tty" "$tool" "$ctx" >> "$audit_file" 2>/dev/null
}

# End timing a tool
# Usage: sysmedic_time_end "tool-name" [exit-code] [extra-notes]
sysmedic_time_end() {
    local tool="${1:-unknown}"
    local exit_code="${2:-0}"
    local ctx="${3:-}"
    local audit_file
    audit_file=$(_sysmedic_audit_file)

    local ts_file="/tmp/sysmedic-timing-${tool}-$$.ts"
    local start_time
    start_time=$(cat "$ts_file" 2>/dev/null || echo "")

    if [ -n "$start_time" ]; then
        local end_time
        end_time=$(date +%s.%N)
        local duration
        duration=$(awk "BEGIN {printf \"%.3f\", $end_time - $start_time}")

        local tty
        tty=$(tty 2>/dev/null | sed 's|/dev/||')
        [ -z "$tty" ] && tty="ai:${SYSMEDIC_AI:-script}"

        local status="OK"
        [ "$exit_code" != "0" ] && status="EXIT=$exit_code"

        printf '%s [%s] TIMING end: %s duration=%.3fs status=%s %s\n' \
            "$(date -Is)" "$tty" "$tool" "$duration" "$status" "$ctx" >> "$audit_file" 2>/dev/null

        rm -f "$ts_file"
    else
        # No start recorded
        local tty
        tty=$(tty 2>/dev/null | sed 's|/dev/||')
        [ -z "$tty" ] && tty="ai:${SYSMEDIC_AI:-script}"
        printf '%s [%s] TIMING end: %s (no start record) status=%s %s\n' \
            "$(date -Is)" "$tty" "$tool" "$exit_code" "$ctx" >> "$audit_file" 2>/dev/null
    fi
}

# Auto-timing wrapper for main() functions
# Usage in a tool:
#   main() { ... }
#   sysmedic_time_main "tool-name" "$@"
sysmedic_time_main() {
    local tool="${1:-unknown}"
    shift

    # Check for --time flag
    local do_time=0
    local filtered_args=()
    for arg in "$@"; do
        if [ "$arg" = "--time" ] || [ "$arg" = "-t" ]; then
            do_time=1
        else
            filtered_args+=("$arg")
        fi
    done

    if [ "$do_time" = 1 ]; then
        sysmedic_time_start "$tool" "${filtered_args[*]}"
        local rc=0
        main "${filtered_args[@]}" || rc=$?
        sysmedic_time_end "$tool" "$rc"
        exit "$rc"
    else
        main "$@"
    fi
}

# Simple one-liner for inline timing
# Usage: sysmedic_time "tool-name" command [args...]
sysmedic_time() {
    local tool="$1"
    shift
    sysmedic_time_start "$tool" "$*"
    local rc=0
    "$@" || rc=$?
    sysmedic_time_end "$tool" "$rc"
    return "$rc"
}