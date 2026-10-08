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

# Remote AI is on: anything the AI runs that isn't read-only waits for a keypress on the device itself
# (console 12, sysmedic-confirm). Children of a confirmed command (e.g. a test's own shell) don't ask again.
if [ -n "${SYSMEDIC_AI:-}" ] && [ -n "${BASH_EXECUTION_STRING:-}" ] && [ -e /run/sysmedic/remote-ai.on ] \
        && [ -z "${SYSMEDIC_CONFIRMED:-}" ]; then
    if ! /usr/local/bin/sysmedic-ask --is-read-only "$BASH_EXECUTION_STRING" >/dev/null 2>&1; then
        if /usr/local/sbin/sysmedic-confirm --who "AI ($SYSMEDIC_AI) while remote AI is on" --what "$BASH_EXECUTION_STRING"; then
            export SYSMEDIC_CONFIRMED=1
        else
            exit 126
        fi
    fi
fi

# AI shells: a command that doesn't exist says so plainly, so a made-up tool is never mistaken for a result.
if [ -n "${SYSMEDIC_AI:-}" ]; then
    command_not_found_handle() {
        printf "SysMedic: '%s' does not exist on this rescue system. Don't invent tools: use 'sysmedic-tests list' for the real tests, or tell the engineer there isn't one.\n" "$1" >&2
        printf '%s [ai:%s] NOT FOUND: %s\n' "$(date -Is)" "$SYSMEDIC_AI" "$1" >> "$(_sysmedic_audit_file)" 2>/dev/null
        return 127
    }
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
