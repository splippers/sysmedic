#!/usr/bin/env python3
"""etl_dump — one .etl (Windows ETW trace) file to JSON lines, using the vendored etl-parser.

Each decoded event: {"t": time, "p": provider/event name, "f": {field: text}}. The last line is
{"summary": {"events": n, "undecoded": n, "error": "..."}}. Run per file (sysmedic-win etl does,
with a time limit) so one awkward trace can't stall the rest.
"""
import json
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor"))

from construct import Container, ListContainer  # noqa: E402
from etl.error import (EtwVersionNotFound, EventIdNotFound, EventTypeNotFound, GroupNotFound,  # noqa: E402
                       GuidNotFound, InvalidType, TlMetaDataNotFound, VersionNotFound)
from etl.etl import IEtlFileObserver, build_from_stream  # noqa: E402

DECODE_ERRORS = (EtwVersionNotFound, EventIdNotFound, GuidNotFound, TlMetaDataNotFound, InvalidType,
                 GroupNotFound, VersionNotFound, EventTypeNotFound)


def text(v):
    t = getattr(v, "type", None)
    try:
        if t == "WString":
            return bytearray(v.string[:-2]).decode("utf-16le", "replace")
        if t == "CString":
            return bytearray(v.string[:-1]).decode("latin-1")
        if t == "Guid":
            i = v.inner
            return f"{i.data1:08x}-{i.data2:04x}-{i.data3:04x}-{bytes(i.data4).hex()}"
    except (AttributeError, TypeError, ValueError):
        pass
    if isinstance(v, (bytes, bytearray, ListContainer)):
        return bytes(bytearray(v))[:64].hex()
    if isinstance(v, Container):
        return ""
    return str(v)


class Dump(IEtlFileObserver):
    def __init__(self):
        self.events = self.undecoded = 0

    def emit(self, when, name, fields):
        self.events += 1
        print(json.dumps({"t": when, "p": name, "f": {k: text(v)[:400] for k, v in fields if not k.startswith("_")}}))

    def on_event_record(self, event, boot_time):
        try:
            when = event.get_timestamp(boot_time)
        except Exception:  # noqa: BLE001
            when = ""
        try:
            tl = event.parse_tracelogging()
            self.emit(when, tl.get_name(), tl.items())
            return
        except TlMetaDataNotFound:
            pass
        except DECODE_ERRORS:
            self.undecoded += 1
            return
        try:
            etw = event.parse_etw()
            self.emit(when, etw.__class__.__name__, ((f.name, etw.source[f.name]) for f in etw.pattern.subcons))
        except DECODE_ERRORS:
            self.undecoded += 1
        except Exception:  # noqa: BLE001  (a malformed record shouldn't end the file)
            self.undecoded += 1

    def on_trace_record(self, event):
        pass

    def on_perfinfo_trace(self, obj, boot_time):
        pass

    def on_system_trace(self, obj):
        pass

    def on_win_trace(self, event):
        try:
            etw = event.parse_etw()
            self.emit("", etw.__class__.__name__, ((f.name, etw.source[f.name]) for f in etw.pattern.subcons))
        except Exception:  # noqa: BLE001
            self.undecoded += 1


def main(path):
    d = Dump()
    err = ""
    try:
        with open(path, "rb") as f:
            build_from_stream(f.read()).parse(d)
    except Exception as e:  # noqa: BLE001  (report, don't crash: compressed or unknown traces)
        err = f"{type(e).__name__}: {e}"[:160]
    print(json.dumps({"summary": {"events": d.events, "undecoded": d.undecoded, "error": err}}))


if __name__ == "__main__":
    main(sys.argv[1])
