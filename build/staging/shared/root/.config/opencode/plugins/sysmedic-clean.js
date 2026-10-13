// SysMedic: nothing reaches the cloud model uncleaned.
// Every tool's result (read, grep, …) passes through sysmedic-redact on the laptop before OpenCode sends it, and the
// file tools can't open the customer's own folders (C:\Users, /home) unless the engineer recorded the customer's
// agreement (sysmedic-consent users). The shell has the same rules (/etc/sysmedic/audit.sh) and is cleaned there.
// OpenCode's read tool must stay available: Zen's free tier refuses requests without it.
//
// OpenCode 2 format: a default export {id, setup}. The 1.x form (a named function returning hooks) is refused by
// OpenCode 2 with only a log warning, and then nothing is cleaned: sysmedic-ai-session checks this plugin loaded.
import { spawnSync } from "node:child_process"
import { existsSync } from "node:fs"

const REDACT = "/usr/local/bin/sysmedic-redact"
const CONSENT = "/run/sysmedic/consent/users"
const USER_DIRS = /(^|["\/\\])(users|home)([\/\\]|"|$)/i      // relative paths too ("Users/anna")
const ENGINEER_ONLY = /system-connections|vault-fs|show-password|redact\.json|\/run\/sysmedic\/consent/
const PATH_KEYS = ["path", "paths", "filePath", "file_path", "pattern", "include", "directory", "dir", "cwd", "uri"]
const KEEP = new Set(["type", "mime", "encoding", "status", "tool", "id", "sessionID", "messageID", "agent"])
const SEP = "\n\u0000SYSMEDIC_PART\u0000\n"

// One sysmedic-redact run for every string in the result (it keeps placeholders consistent across them)
function cleanAll(strings) {
  if (!strings.length) return strings
  if (!existsSync(REDACT)) return strings.map(() => "[SysMedic: output withheld: the cleaner is missing]")
  const r = spawnSync(REDACT, [], { input: strings.join(SEP), encoding: "utf8", timeout: 60000, maxBuffer: 64 * 1024 * 1024 })
  const parts = r.status === 0 && typeof r.stdout === "string" ? r.stdout.split(SEP) : []
  // If cleaning fails, send nothing rather than the raw text
  return parts.length === strings.length ? parts : strings.map(() => "[SysMedic: output withheld: it couldn't be cleaned]")
}

function strings(o, out = [], key = "") {
  if (typeof o === "string") { if (!KEEP.has(key) && o) out.push(o) }
  else if (Array.isArray(o)) o.forEach((v) => strings(v, out, key))
  else if (o && typeof o === "object") for (const [k, v] of Object.entries(o)) strings(v, out, k)
  return out
}

function replace(o, it, key = "") {
  if (typeof o === "string") return !KEEP.has(key) && o ? it.next().value : o
  if (Array.isArray(o)) return o.map((v) => replace(v, it, key))
  if (o && typeof o === "object") return Object.fromEntries(Object.entries(o).map(([k, v]) => [k, replace(v, it, k)]))
  return o
}

function pathArgs(input) {
  if (!input || typeof input !== "object") return ""
  return JSON.stringify(PATH_KEYS.filter((k) => k in input).map((k) => input[k]))
}

export default {
  id: "sysmedic-clean",
  async setup(ctx) {
    await ctx.tool.hook("execute.before", (event) => {
      if (event.tool === "shell" || event.tool === "bash") return        // audit.sh: refusals and cleaning
      const args = pathArgs(event.input)
      if (ENGINEER_ONLY.test(args)) {
        throw new Error("SysMedic: refused: Wi-Fi passwords, the vault, the cleaning map and consent records are the engineer's.")
      }
      if (USER_DIRS.test(args) && !existsSync(CONSENT)) {
        throw new Error("SysMedic: the customer's own folders (C:\\Users, /home) are closed to the AI without the customer's " +
          "explicit agreement. Ask the engineer: with the customer's OK they record it on the laptop (sysmedic-consent users).")
      }
    })
    await ctx.tool.hook("execute.after", (event) => {
      if (event.tool === "shell" || event.tool === "bash") return        // already cleaned inside the shell
      if (event.status === "completed" && event.result) {
        const cleaned = cleanAll(strings(event.result))
        event.result = replace(event.result, cleaned[Symbol.iterator]())
      } else if (event.status === "error" && event.error && typeof event.error.message === "string") {
        event.error.message = cleanAll([event.error.message])[0]
      }
    })
  },
}
