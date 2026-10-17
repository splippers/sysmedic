"""Marvin: Discord front end for an OpenCode server. Chat only; allowlisted; rate-limited."""
import os, re, time, asyncio, collections
import discord, requests

TOKEN = os.environ["DISCORD_TOKEN"]
URL = os.environ.get("OPENCODE_URL", "http://opencode:4096")
AUTH = ("opencode", os.environ.get("OPENCODE_SERVER_PASSWORD", ""))
ids = lambda k: {int(x) for x in os.environ.get(k, "").replace(" ", "").split(",") if x}
USERS, CHANNELS = ids("ALLOWED_USER_IDS"), ids("ALLOWED_CHANNEL_IDS")
PER_USER_PER_MIN = 4
SECRET = re.compile(r"(?i)(token|secret|password|api[_-]?key)\s*[:=]\s*\S+|[A-Za-z0-9_\-]{32,}")
PRIVATE_IP = re.compile(r"\b(?:10|192\.168|172\.(?:1[6-9]|2\d|3[01]))\.\d+\.\d+(?:\.\d+)?\b")

intents = discord.Intents.default(); intents.message_content = True
client = discord.Client(intents=intents)
hits = collections.defaultdict(collections.deque)
sessions = {}  # channel id -> opencode session id

def limited(uid):
    q, now = hits[uid], time.time()
    while q and now - q[0] > 60: q.popleft()
    q.append(now)
    return len(q) > PER_USER_PER_MIN

def ask(chan, text):
    sid = sessions.get(chan)
    if not sid:
        sid = requests.post(f"{URL}/session", json={}, auth=AUTH, timeout=15).json()["id"]
        sessions[chan] = sid
    r = requests.post(f"{URL}/session/{sid}/message", auth=AUTH, timeout=120,
                      json={"parts": [{"type": "text", "text": text}]})
    r.raise_for_status()
    return "".join(p.get("text", "") for p in r.json().get("parts", []) if p.get("type") == "text")

def clean(out):
    if SECRET.search(out) or PRIVATE_IP.search(out):
        return "I can't share that."
    return out.replace("@everyone", "everyone").replace("@here", "here")[:1900] or "..."

@client.event
async def on_message(m):
    if m.author.bot or m.author.id not in USERS:
        return
    dm = isinstance(m.channel, discord.DMChannel)
    if not (dm or (m.channel.id in CHANNELS and client.user in m.mentions)):
        return
    text = m.content.replace(f"<@{client.user.id}>", "").strip()
    if not text: return
    if limited(m.author.id):
        await m.reply("Slow down.", mention_author=False); return
    async with m.channel.typing():
        try:
            out = await asyncio.to_thread(ask, m.channel.id, text)
        except Exception:
            out = "Backend unavailable."
    await m.reply(clean(out), mention_author=False, allowed_mentions=discord.AllowedMentions.none())

client.run(TOKEN)
