"""lessons — read SysMedic's tutorials (Markdown with front matter) into steps.

A lesson is `NN-name.md`: a front-matter block (title, summary, time, level), then one `## ` heading per step.
Inside a step: paragraphs and tables; `> Why: …` lines (the reason, shown dim); and fenced command blocks:

    ```run     a read-only command the runner may run for you on request (must be in RUN_ALLOWED)
    ```cmd     a command to show only: the engineer types it, usually on console 2

The runner never runs a `cmd` block and refuses a `run` block outside RUN_ALLOWED, so a lesson can teach a repair
without ever being able to start one.
"""
import os
import re
import shlex

DIRS = ["/usr/local/share/doc/sysmedic/docs/tutorials"]
RUN_ALLOWED = {
    ("lsblk",), ("sysmedic-scan",), ("sysmedic-hwtest", "report"), ("sysmedic-connect", "--status"),
    ("sysmedic-vault", "status"),
}


def lesson_dir():
    d = os.environ.get("SYSMEDIC_LESSONS")
    return d if d else next((x for x in DIRS if os.path.isdir(x)), DIRS[0])


def run_allowed(command):
    try:
        return tuple(shlex.split(command)) in RUN_ALLOWED
    except ValueError:
        return False


def parse(text):
    """-> {title, summary, time, level, steps: [{title, body: [str], why: [str], blocks: [(kind, text)]}]}"""
    meta, body = {}, text
    m = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if m:
        for line in m.group(1).splitlines():
            k, _, v = line.partition(":")
            meta[k.strip()] = v.strip()
        body = text[m.end():]
    steps, cur, fence = [], None, None
    for line in body.splitlines():
        if fence is not None:
            if line.startswith("```"):
                cur["blocks"].append((fence[0], "\n".join(fence[1])))
                cur["body"].append(f"\0{len(cur['blocks']) - 1}")     # where the block sits among the text
                fence = None
            else:
                fence[1].append(line)
            continue
        if line.startswith("## "):
            cur = {"title": line[3:].strip(), "body": [], "why": [], "blocks": []}
            steps.append(cur)
        elif cur is None:
            continue
        elif line.startswith("```"):
            fence = (line[3:].strip() or "text", [])
        elif line.startswith("> Why:"):
            cur["why"].append(line[6:].strip())
        else:
            cur["body"].append(line)
    meta["steps"] = steps
    return meta


def load(path):
    with open(path, encoding="utf-8") as f:
        lesson = parse(f.read())
    lesson["id"] = re.sub(r"^\d+-", "", os.path.basename(path)[:-3])
    lesson["path"] = path
    return lesson


def catalogue(directory=None):
    d = directory or lesson_dir()
    if not os.path.isdir(d):
        return []
    return [load(os.path.join(d, f)) for f in sorted(os.listdir(d)) if re.match(r"\d+-.*\.md$", f)]
