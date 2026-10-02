# SysMedic audit trail — appends every command to the session's audit.log.
# Sourced via BASH_ENV for commands the AI runs (SYSMEDIC_AI=opencode|ask),
# and from /root/.bashrc for commands typed at a console.

_sysmedic_audit_file() {
    local d
    d=$(readlink -f /run/sysmedic/latest 2>/dev/null)
    if [ -n "$d" ] && [ -d "$d" ]; then echo "$d/audit.log"; else mkdir -p /run/sysmedic; echo /run/sysmedic/audit.log; fi
}

if [ -n "${SYSMEDIC_AI:-}" ] && [ -n "${BASH_EXECUTION_STRING:-}" ]; then
    printf '%s [ai:%s] %s\n' "$(date -Is)" "$SYSMEDIC_AI" "${BASH_EXECUTION_STRING//$'\n'/ ⏎ }" \
        >> "$(_sysmedic_audit_file)" 2>/dev/null
fi

if [[ $- == *i* ]] && [ -z "${SYSMEDIC_AI:-}" ]; then
    _sysmedic_log_cmd() {
        local c
        c=$(HISTTIMEFORMAT='' history 1 | sed 's/^ *[0-9]* *//')
        if [ -n "$c" ] && [ "$c" != "${_sysmedic_last:-}" ]; then
            printf '%s [%s] %s\n' "$(date -Is)" "$(t=${SYSMEDIC_TTY:-$(tty 2>/dev/null)}; echo ${t#/dev/})" "$c" >> "$(_sysmedic_audit_file)" 2>/dev/null
        fi
        _sysmedic_last=$c
    }
    case "${PROMPT_COMMAND:-}" in *_sysmedic_log_cmd*) ;; *) PROMPT_COMMAND="_sysmedic_log_cmd${PROMPT_COMMAND:+; $PROMPT_COMMAND}" ;; esac
fi
