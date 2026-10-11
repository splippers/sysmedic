#!/usr/bin/env python3
"""SysMedic Timing Library (Python) — execution time logging for Python-based sysmedic tools.

Usage:
    from timing import sysmedic_time_start, sysmedic_time_end, timed_main

    # Option 1: manual timing
    sysmedic_time_start("sysmedic-scan", "full scan")
    ... do work ...
    sysmedic_time_end("sysmedic-scan", exit_code=0, context="completed")

    # Option 2: decorator for main()
    @timed_main("sysmedic-win")
    def main(args):
        ...

    # Option 3: context manager
    with TimedSection("sysmedic-hwtest", "cpu stress"):
        run_test()
"""

import inspect
import os
import sys
import time
import subprocess
from contextlib import contextmanager
from functools import wraps


def _sysmedic_audit_file():
    """Returns the session audit log path."""
    try:
        d = subprocess.run(
            ["readlink", "-f", "/run/sysmedic/latest"],
            capture_output=True, text=True, timeout=2
        ).stdout.strip()
        if d and os.path.isdir(d):
            return os.path.join(d, "audit.log")
    except Exception:
        pass
    os.makedirs("/run/sysmedic", exist_ok=True)
    return "/run/sysmedic/audit.log"


def _get_tty():
    """Get current TTY identifier."""
    try:
        tty = os.ttyname(0)
        return tty.replace("/dev/", "")
    except OSError:
        pass
    if os.environ.get("SYSMEDIC_AI"):
        return f"ai:{os.environ['SYSMEDIC_AI']}"
    return "script"


_timing_starts = {}


def _audit(line):
    """Append to the audit log; timing must never break the tool it measures."""
    try:
        with open(_sysmedic_audit_file(), "a") as f:
            f.write(line)
    except OSError:
        pass


def sysmedic_time_start(tool: str, context: str = ""):
    """Record start time for a tool."""
    _timing_starts[tool] = time.time()
    tty = _get_tty()
    ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    # Fix timezone format
    if len(ts) == 24:
        ts = ts[:-2] + ":" + ts[-2:]
    _audit(f"{ts} [{tty}] TIMING start: {tool} {context}\n")


def sysmedic_time_end(tool: str, exit_code: int = 0, context: str = ""):
    """Record end time and duration for a tool."""
    start_time = _timing_starts.pop(tool, None)
    tty = _get_tty()
    ts = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    if len(ts) == 24:
        ts = ts[:-2] + ":" + ts[-2:]

    if start_time is not None:
        duration = time.time() - start_time
        status = "OK" if exit_code == 0 else f"EXIT={exit_code}"
        _audit(f"{ts} [{tty}] TIMING end: {tool} duration={duration:.3f}s status={status} {context}\n")
    else:
        status = "OK" if exit_code == 0 else f"EXIT={exit_code}"
        _audit(f"{ts} [{tty}] TIMING end: {tool} (no start record) status={status} {context}\n")


@contextmanager
def TimedSection(tool: str, context: str = ""):
    """Context manager for timing a code block."""
    sysmedic_time_start(tool, context)
    try:
        yield
        sysmedic_time_end(tool, 0, context)
    except SystemExit as e:
        sysmedic_time_end(tool, e.code if isinstance(e.code, int) else 1, context)
        raise
    except Exception:
        sysmedic_time_end(tool, 1, context + " ERROR")
        raise


def timed_main(tool_name: str):
    """Decorator for main() function to add --time flag support.

    Usage:
        @timed_main("sysmedic-scan")
        def main(args):
            ...

    Adds --time/-t flag that enables timing when present.
    """
    def decorator(main_func):
        # Most sysmedic tools have main() with no parameters and read sys.argv themselves
        takes_args = bool(inspect.signature(main_func).parameters)

        @wraps(main_func)
        def wrapper(args=None):
            from_argv = args is None
            if from_argv:
                args = sys.argv[1:]

            do_time = "--time" in args or "-t" in args
            filtered_args = [a for a in args if a not in ("--time", "-t")]
            if from_argv:
                sys.argv[1:] = filtered_args      # so tools that read sys.argv don't see --time

            def call():
                return main_func(filtered_args) if takes_args else main_func()

            if do_time:
                sysmedic_time_start(tool_name, " ".join(filtered_args))
                try:
                    rc = call()
                    sysmedic_time_end(tool_name, rc or 0, "completed")
                    return rc
                except SystemExit as e:
                    rc = e.code if isinstance(e.code, int) else 1
                    sysmedic_time_end(tool_name, rc, "exited")
                    raise
                except Exception as e:
                    sysmedic_time_end(tool_name, 1, f"error: {e}")
                    raise
            else:
                return call()

        return wrapper
    return decorator


# Auto-enable timing if SYSMEDIC_TIME=1 env var is set
if os.environ.get("SYSMEDIC_TIME") == "1":
    # Wrap sys.exit to capture timing
    original_exit = sys.exit
    def timed_exit(code=0):
        # Find the most recent timing start
        if _timing_starts:
            tool = list(_timing_starts.keys())[-1]
            sysmedic_time_end(tool, code, "auto")
        original_exit(code)
    sys.exit = timed_exit