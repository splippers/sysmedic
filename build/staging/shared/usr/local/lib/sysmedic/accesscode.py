"""accesscode — the engineer's own remote access code, kept in the encrypted vault.

The phone dashboard and the remote AI terminal normally use a random secret that changes every boot (shown as a QR
code). For a laptop that can't scan one, the engineer can set a short code of their own instead, once: it lives in
the vault, so it survives reboots and is the same on every job, and it is only ever accepted over HTTPS (the
dashboard's port 8443, the AI terminal's 8444), never over the plain-HTTP dashboard port, so it doesn't cross the
customer's network in clear text. The AI can't read the vault, and the cleaner masks the code in anything it sends.
"""
import os
import re
import secrets

FILE = "/run/sysmedic/vault-fs/access-code"
MIN_LEN, MAX_LEN = 10, 48
WORDS = """acorn amber anvil apple arrow aspen atlas azure badge baker basil beach birch blaze bloom bonus brave
breeze brick bridge brook cabin cable camel candy canoe cedar chalk charm chess cider cliff cloud clover cobalt
comet coral crane crisp daisy delta denim dune eagle ember fable falcon fern fiddle flint forest frost gale garnet
ginger glade globe gold grain grove harbor hazel heron honey iron island ivory jade jasper juniper kayak kettle
lantern larch lemon lilac linen lotus lunar maple marsh meadow mint misty moss nectar nickel noble oak ocean olive
onyx opal orbit otter pearl pebble pine plum polar poppy quartz quill raven reef ridge river robin ruby saddle sage
sand silk silver slate solar spruce stone storm sunny swift tango thistle tiger timber topaz tulip umber valley
velvet violet walnut willow winter wren yarrow zephyr""".split()


def get():
    """The saved code, or '' (vault locked, or none set)."""
    try:
        code = open(FILE).read().strip()
    except OSError:
        return ""
    return code if check(code) is None else ""


def check(code):
    """None if the code is acceptable, else why not."""
    if not re.fullmatch(r"[A-Za-z0-9._-]+", code or ""):
        return "use letters, digits, dot, dash or underscore only (no spaces)"
    if len(code) < MIN_LEN:
        return f"at least {MIN_LEN} characters: it protects the AI terminal on a network you don't control"
    if len(code) > MAX_LEN:
        return f"at most {MAX_LEN} characters"
    if len(set(code.lower())) < 5:
        return "too repetitive"
    if code.isdigit() and len(code) < 14:
        return "digits only needs 14 or more characters"
    return None


def suggest(n=5):
    """Five random short words: easy to read out and type, about 35 bits."""
    return "-".join(secrets.choice(WORDS) for _ in range(n))
