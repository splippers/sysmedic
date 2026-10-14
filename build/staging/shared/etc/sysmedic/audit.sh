# SysMedic audit trail — appends every command to the session's audit.log.
# Sourced via BASH_ENV for commands the AI runs (SYSMEDIC_AI=opencode|ask),
# and from /root/.bashrc for commands typed at a console.

_sysmedic_audit_file() {
    local d
    d=$(readlink -f /run/sysmedic/latest 2>/dev/null)
    if [ -n "$d" ] && [ -d "$d" ]; then echo "$d/audit.log"; else mkdir -p /run/sysmedic; echo /run/sysmedic/audit.log; fi
}

# The cloud AI's command re-run below (output cleaned): already logged and checked by its parent
_sysmedic_rerun=
[ -n "${SYSMEDIC_REDACTED:-}" ] && [ "${BASH_EXECUTION_STRING:-}" = "$SYSMEDIC_REDACTED" ] && _sysmedic_rerun=1

if [ -n "${SYSMEDIC_AI:-}" ] && [ -n "${BASH_EXECUTION_STRING:-}" ] && [ -z "$_sysmedic_rerun" ]; then
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

# The customer's own folders (C:\Users, /home) are closed to the AI until the engineer records the customer's
# explicit agreement on this keyboard (sysmedic-consent users). Consent records are never the AI's to make.
if [ -n "${SYSMEDIC_AI:-}" ] && [ -n "${BASH_EXECUTION_STRING:-}" ] && [ -z "$_sysmedic_rerun" ]; then
    if [[ "$BASH_EXECUTION_STRING" =~ sysmedic-consent|/run/sysmedic/consent|redact\.json|sysmedic-redact[[:space:]]+--show|system-connections|vault-fs|show-secrets|show-password|[[:space:]]-s[[:space:]].*(wifi|connection)|802-11-wireless-security ]]; then
        echo "SysMedic: REFUSED: consent, the cleaning map, the vault and Wi-Fi passwords are the engineer's." >&2
        printf '%s [ai:%s] REFUSED (consent/cleaning map): %s\n' "$(date -Is)" "$SYSMEDIC_AI" "${BASH_EXECUTION_STRING//$'\n'/ ⏎ }" >> "$(_sysmedic_audit_file)" 2>/dev/null
        exit 126
    fi
    # A plain text write (cat > FILE <<'EOF' … EOF, quoted terminator so nothing in it runs or expands, and nothing
    # after it) only stores words: check its first line, not the text (the AI's report may mention C:\Users).
    _sysmedic_check=$BASH_EXECUTION_STRING
    _sysmedic_first=${BASH_EXECUTION_STRING%%$'\n'*}
    _sysmedic_re=$'^[[:space:]]*cat[[:space:]]+(>>?[[:space:]]*[^][:space:]<>;&|$`()\'"]+[[:space:]]+<<-?[[:space:]]*|<<-?[[:space:]]*)([\'"])([A-Za-z_][A-Za-z0-9_]*)[\'"]([[:space:]]+>>?[[:space:]]*[^][:space:]<>;&|$`()\'"]+)?[[:space:]]*$'
    if [[ "$_sysmedic_first" =~ $_sysmedic_re ]] && [[ "${BASH_REMATCH[1]}" == *">"* || "${BASH_REMATCH[4]}" == *">"* ]] \
            && [[ "${BASH_REMATCH[1]}" != *">"* || "${BASH_REMATCH[4]}" != *">"* ]]; then
        _sysmedic_w=${BASH_REMATCH[3]}
        _sysmedic_body=${BASH_EXECUTION_STRING#*$'\n'}
        _sysmedic_body=${_sysmedic_body%$'\n'}
        _sysmedic_last=${_sysmedic_body##*$'\n'}
        _sysmedic_last=${_sysmedic_last#"${_sysmedic_last%%[!$'\t']*}"}
        if [ "$_sysmedic_last" = "$_sysmedic_w" ] && [ "$(grep -cx $'\t*'"$_sysmedic_w" <<< "$_sysmedic_body")" = 1 ]; then
            _sysmedic_check=$_sysmedic_first
        fi
    fi
    if [ ! -e /run/sysmedic/consent/users ] && [[ "$_sysmedic_check" =~ [/\\]([Uu][Ss][Ee][Rr][Ss]|home)([/\\\"\'*[:space:]]|$) ]]; then
        echo "SysMedic: the customer's own folders (C:\\Users, /home) are closed to the AI without the customer's explicit agreement. Ask the engineer: with the customer's OK they record it on the laptop (sysmedic-consent users)." >&2
        printf '%s [ai:%s] REFUSED (user folders, no consent): %s\n' "$(date -Is)" "$SYSMEDIC_AI" "${BASH_EXECUTION_STRING//$'\n'/ ⏎ }" >> "$(_sysmedic_audit_file)" 2>/dev/null
        exit 126
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

# Cloud AI: everything the command prints goes through sysmedic-redact before the cloud sees it (names, the company,
# its servers, keys, personal file names: replaced with placeholders, consistently for the visit).
if [ "${SYSMEDIC_AI:-}" = opencode ] && [ -n "${BASH_EXECUTION_STRING:-}" ] && [ -z "${SYSMEDIC_REDACTED:-}" ]; then
    export SYSMEDIC_REDACTED="$BASH_EXECUTION_STRING"
    bash -c "$BASH_EXECUTION_STRING" 2>&1 | /usr/local/bin/sysmedic-redact
    exit "${PIPESTATUS[0]}"
fi
