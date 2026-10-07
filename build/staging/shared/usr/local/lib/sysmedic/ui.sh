# ui.sh — SysMedic's one look for console output, for the shell tools (Python tools use ui.py: same rules).
#   . /usr/local/lib/sysmedic/ui.sh
#   ui_banner "Title" "subtitle"     ▌SysMedic  Title / dim subtitle / dim rule
#   ui_section "Title"               bold title and a dim rule
#   ui_ok / ui_warn / ui_fail / ui_info / ui_run "text" ["detail"]    ✔ ▲ ✖ ● ► marks, detail dimmed underneath
# The marks need SysMedic's console font (SysMedic-Terminus22x11). NO_COLOR=1 or a non-terminal turns colour off.

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    _U_ACC=$'\033[1;36m'; _U_B=$'\033[1m'; _U_D=$'\033[2m'; _U_G=$'\033[0;32m'; _U_Y=$'\033[1;33m'
    _U_R=$'\033[1;31m'; _U_C=$'\033[0;36m'; _U_N=$'\033[0m'
else
    _U_ACC= _U_B= _U_D= _U_G= _U_Y= _U_R= _U_C= _U_N=
fi
_ui_width() { local w; w=$(tput cols 2>/dev/null || echo 96); [ "$w" -gt 120 ] && w=120; echo "$w"; }
_ui_line() { local n=$1 s; printf -v s '%*s' "$n" ''; printf '%s' "${s// /─}"; }

ui_rule()    { echo "  ${_U_D}$(_ui_line $(( $(_ui_width) - 4 )))${_U_N}"; }
ui_banner()  { echo "${_U_ACC}▌${_U_N}${_U_B}SysMedic${_U_N}  ${_U_B}$1${_U_N}"; [ -n "${2:-}" ] && echo "  ${_U_D}$2${_U_N}"; ui_rule; }
ui_section() { local pad=$(( $(_ui_width) - ${#1} - 6 )); [ $pad -lt 4 ] && pad=4; echo; echo "  ${_U_B}$1${_U_N} ${_U_D}$(_ui_line $pad)${_U_N}"; }
_ui_item()   { echo "  $1$2${_U_N}  $3"; [ -n "${4:-}" ] && echo "     ${_U_D}$4${_U_N}"; return 0; }
ui_ok()      { _ui_item "$_U_G" "✔" "$1" "${2:-}"; }
ui_warn()    { _ui_item "$_U_Y" "▲" "$1" "${2:-}"; }
ui_fail()    { _ui_item "$_U_R" "✖" "${_U_R}$1${_U_N}" "${2:-}"; }
ui_info()    { _ui_item "$_U_C" "●" "$1" "${2:-}"; }
ui_run()     { _ui_item "$_U_ACC" "►" "$1" "${2:-}"; }
