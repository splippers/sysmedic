"""formslib — the logic behind SysMedic Forms: read a tool's spec, check what the person filled in, build the command.

No GTK in here, so it is tested without a screen (test_formslib.py). A spec is a TOML file; one per console tool:

  title = "Recover deleted files"        window title
  folder = "Recover and clone"            desktop folder it is listed in
  icon = "document-revert"                icon name
  summary = "..."                         one line under the title, plain English
  risk = "read" | "change" | "destroy"    what the tool does to the machine being repaired
  root = true                             needs root (sudo -n is added when we are not root)
  progress = 'regex with one group'       percent in the tool's output, for the progress bar
  done = "text"                           shown when it finishes ({field} works here too): where to find the result
  env = { TERM = "dumb" }                 extra environment for the tool
  command = ["tool", "-x", "{field}", {if = "flag", args = ["-v"]}]

  [[field]]
  id = "disk"   label = "..."   type = "disk|folder|file|choice|bool|text|number"   (+ options, default, min, max, help)

Arguments are passed as a list, never through a shell, so nothing a person types can run as a command.
"""
import json
import os
import re
import subprocess
import tomllib

RISKS = ("read", "change", "destroy")
TYPES = ("disk", "folder", "file", "choice", "bool", "text", "number")


class SpecError(Exception):
    pass


def load_spec(path):
    with open(path, "rb") as f:
        s = tomllib.load(f)
    s["_path"] = path
    s["_name"] = os.path.splitext(os.path.basename(path))[0]
    for k in ("title", "summary", "command"):
        if not s.get(k):
            raise SpecError(f"{path}: missing '{k}'")
    s.setdefault("risk", "read")
    s.setdefault("folder", "Other")
    s.setdefault("icon", "applications-system")
    s.setdefault("root", False)
    s.setdefault("field", [])
    if s["risk"] not in RISKS:
        raise SpecError(f"{path}: risk must be one of {RISKS}")
    ids = set()
    for fld in s["field"]:
        if fld.get("type") not in TYPES or not fld.get("id") or not fld.get("label"):
            raise SpecError(f"{path}: every field needs id, label and a type from {TYPES}: {fld}")
        if fld["id"] in ids:
            raise SpecError(f"{path}: field '{fld['id']}' appears twice")
        ids.add(fld["id"])
        if fld["type"] == "choice" and not fld.get("options"):
            raise SpecError(f"{path}: choice '{fld['id']}' has no options")
    for item in s["command"]:
        for ref in re.findall(r"\{(\w+)\}", item) if isinstance(item, str) else [item.get("if", "")] + re.findall(r"\{(\w+)\}", " ".join(item.get("args", []))):
            if ref and ref not in ids:
                raise SpecError(f"{path}: the command uses '{ref}', which is not a field")
    return s


def load_all(directory):
    """{name: spec} for every spec in a folder; a broken one is skipped and reported in errors."""
    specs, errors = {}, []
    for fn in sorted(os.listdir(directory)):
        if fn.endswith(".toml"):
            try:
                s = load_spec(os.path.join(directory, fn))
                specs[s["_name"]] = s
            except (SpecError, tomllib.TOMLDecodeError, OSError) as e:
                errors.append(f"{fn}: {e}")
    return specs, errors


def defaults(spec):
    out = {}
    for f in spec["field"]:
        d = f.get("default")
        if f["type"] == "bool":
            out[f["id"]] = bool(d)
        elif f["type"] == "choice":
            out[f["id"]] = d if d in [o["value"] if isinstance(o, dict) else o for o in f["options"]] else \
                (f["options"][0]["value"] if isinstance(f["options"][0], dict) else f["options"][0])
        else:
            out[f["id"]] = "" if d is None else str(d)
    return out


def problems(spec, values):
    """Plain-English reasons the form can't run yet (empty list = fine)."""
    bad = []
    for f in spec["field"]:
        v, label = values.get(f["id"], ""), f["label"].rstrip(":")
        if f["type"] == "bool":
            continue
        if f.get("required", True) and v in ("", None):
            bad.append(f"{label}: choose or enter a value")
            continue
        if v in ("", None):
            continue
        if f["type"] == "disk" and not str(v).startswith("/dev/"):
            bad.append(f"{label}: pick a disk from the list")
        elif f["type"] == "folder" and not os.path.isdir(v):
            bad.append(f"{label}: that folder doesn't exist")
        elif f["type"] == "file" and not os.path.isfile(v):
            bad.append(f"{label}: that file doesn't exist")
        elif f["type"] == "number":
            try:
                n = float(v)
            except ValueError:
                bad.append(f"{label}: enter a number")
                continue
            if "min" in f and n < f["min"] or "max" in f and n > f["max"]:
                bad.append(f"{label}: between {f.get('min', '-∞')} and {f.get('max', '∞')}")
        elif f["type"] == "choice":
            allowed = [o["value"] if isinstance(o, dict) else o for o in f["options"]]
            if v not in allowed:
                bad.append(f"{label}: pick one of the choices")
        elif f["type"] == "text" and (str(v).startswith("-") and not f.get("allow_dash")):
            bad.append(f"{label}: can't start with '-'")   # a typed value must never be read as an option
    return bad


def build_command(spec, values, as_root=None):
    """The argument list to run. {id} is replaced inside each argument; {if=..} items add arguments only when ticked/chosen."""
    cmd = []
    for item in spec["command"]:
        if isinstance(item, str):
            cmd.append(re.sub(r"\{(\w+)\}", lambda m: str(values.get(m.group(1), "")), item))
        else:
            v = values.get(item["if"])
            ok = (v == item["equals"]) if "equals" in item else bool(v)
            if ok:
                cmd += [re.sub(r"\{(\w+)\}", lambda m: str(values.get(m.group(1), "")), a) for a in item.get("args", [])]
    if spec["root"] and (os.geteuid() != 0 if as_root is None else not as_root):
        cmd = ["sudo", "-n"] + cmd
    return cmd


ANSI = re.compile(r"\x1b(?:\[[0-9;?]*[ -/]*[@-~]|\][^\x07]*\x07|[()][0-9A-B]|[=>])|\x1b\[[0-9;]*t")


def clean(text):
    """The tool's output without terminal control codes (ncurses tools like PhotoRec draw with them)."""
    return ANSI.sub("", text).replace("\x0f", "")


def finish_text(spec, values):
    return re.sub(r"\{(\w+)\}", lambda m: str(values.get(m.group(1), "")), spec.get("done", ""))


def shown(cmd):
    """The command as a person would read it, for the 'this is what runs' line."""
    return " ".join(c if re.fullmatch(r"[\w@%+=:,./-]+", c) else "'" + c.replace("'", "'\\''") + "'" for c in cmd)


def progress_of(spec, text):
    """Latest percentage in a chunk of the tool's output, or None."""
    rx = spec.get("progress")
    if not rx:
        return None
    last = None
    for m in re.finditer(rx, text):
        try:
            last = max(0.0, min(100.0, float(m.group(1))))
        except (ValueError, IndexError):
            pass
    return last


def _run(cmd):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=15).stdout
    except (OSError, subprocess.TimeoutExpired):
        return ""


def boot_disks():
    """Whole disks SysMedic itself runs from: they are never offered as a target for anything that writes."""
    out = set()
    for mp in ("/cdrom", "/run/live/medium", "/"):
        src = _run(["findmnt", "-no", "SOURCE", mp]).strip().split("[")[0]
        if src.startswith("/dev/"):
            pk = _run(["lsblk", "-no", "PKNAME", src]).strip().splitlines()
            out.add("/dev/" + pk[0] if pk and pk[0] else src)
    return out


def disks(lsblk_json=None):
    """[{path, label, ro, removable, boot}] for the whole disks, labelled by model and size so people recognise them."""
    data = json.loads(lsblk_json) if lsblk_json is not None else json.loads(
        _run(["lsblk", "-J", "-d", "-b", "-o", "PATH,MODEL,SIZE,RO,RM,TRAN,TYPE,SERIAL"]) or '{"blockdevices": []}')
    boot = set() if lsblk_json is not None else boot_disks()
    res = []
    for d in data.get("blockdevices", []):
        if d.get("type") != "disk" or str(d.get("path", "")).startswith("/dev/zram"):
            continue
        size = int(d.get("size") or 0)
        gb = f"{size / 1e12:.1f} TB" if size >= 1e12 else f"{size / 1e9:.0f} GB"
        model = (d.get("model") or "Unnamed drive").strip()
        res.append({"path": d["path"], "ro": bool(d.get("ro")), "removable": bool(d.get("rm")),
                    "serial": (d.get("serial") or "").strip(), "boot": d["path"] in boot,
                    "label": f"{model} · {gb} · {d['path']}" + (" · USB" if d.get("tran") == "usb" else "")})
    return res


def launcher(spec):
    """The .desktop file for a spec's window."""
    return (f"[Desktop Entry]\nType=Application\nName={spec['title']}\nComment={spec['summary']}\n"
            f"Exec=sysmedic-forms {spec['_name']}\nIcon={spec['icon']}\nTerminal=false\n"
            f"Categories=System;X-SysMedic-{re.sub(r'[^A-Za-z]', '', spec['folder'])};\n")
