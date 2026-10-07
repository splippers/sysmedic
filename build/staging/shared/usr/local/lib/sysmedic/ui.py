"""ui — SysMedic's one look for console output (the shell tools use ui.sh, the same rules).

  banner(title, subtitle)       ▌SysMedic  Title
                                   subtitle (dim)
                                ──────────────── (dim rule)
  section(title)                Title ────────── (bold title, dim rule)
  item(sev, text, detail, nxt)  ✔ / ▲ / ✖ / ● coloured mark, text; detail dim underneath; → next step
  chips(counts)                 ✖ 0 critical   ▲ 1 warning   ● 2 notes   ✔ 4 OK

The marks need SysMedic's console font (SysMedic-Terminus22x11, build/make-console-font.py). Colour is off when
the output isn't a terminal or color=False (plain text for summaries the AI and reports read).
"""
import os
import shutil
import sys

MARK = {"critical": "✖", "fail": "✖", "warning": "▲", "warn": "▲", "info": "●", "note": "●", "ok": "✔", "pass": "✔",
        "run": "►", "skip": "□"}
COLOR = {"critical": "\033[1;31m", "fail": "\033[1;31m", "warning": "\033[1;33m", "warn": "\033[1;33m",
         "info": "\033[0;36m", "note": "\033[0;36m", "ok": "\033[0;32m", "pass": "\033[0;32m", "run": "\033[1;36m",
         "skip": "\033[2m", "accent": "\033[1;36m", "bold": "\033[1m", "dim": "\033[2m", "end": "\033[0m"}


class UI:
    def __init__(self, color=None, width=None):
        self.color = sys.stdout.isatty() and not os.environ.get("NO_COLOR") if color is None else color
        self.width = width or min(shutil.get_terminal_size((96, 24)).columns, 120)

    def c(self, key, text):
        return f"{COLOR[key]}{text}{COLOR['end']}" if self.color else text

    def rule(self, indent=2):
        return " " * indent + self.c("dim", "─" * (self.width - indent - 2))

    def banner(self, title, subtitle=""):
        lines = [self.c("accent", "▌") + self.c("bold", "SysMedic") + "  " + self.c("bold", title)]
        if subtitle:
            lines.append("  " + self.c("dim", subtitle))
        lines.append(self.rule())
        return "\n".join(lines)

    def section(self, title):
        pad = max(4, self.width - len(title) - 6)
        return "\n  " + self.c("bold", title) + " " + self.c("dim", "─" * pad)

    def item(self, sev, text, detail="", nxt="", indent=2):
        mark = MARK.get(sev, "●")
        lines = [" " * indent + self.c(sev, mark) + "  " + (self.c(sev, text) if sev in ("critical", "fail") else text)]
        for d in ([detail] if isinstance(detail, str) else detail or []):
            if d:
                lines.append(" " * (indent + 3) + self.c("dim", d))
        if nxt:
            lines.append(" " * (indent + 3) + self.c("bold", "→ ") + nxt)
        return "\n".join(lines)

    def chips(self, counts, labels=(("critical", "critical"), ("warning", "warning"), ("info", "note"), ("ok", "OK"))):
        out = []
        for key, label in labels:
            n = counts.get(key, 0)
            word = label if label in ("OK", "critical") or n == 1 else label + "s"
            text = f"{MARK[key]} {n} {word}"
            out.append(self.c(key, text) if n else self.c("dim", text))
        return "  " + "   ".join(out)

    def kv(self, key, value, width=14):
        return f"  {self.c('dim', (key + ':').ljust(width))} {value}"
