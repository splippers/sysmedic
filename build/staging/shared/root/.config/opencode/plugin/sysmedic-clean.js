// SysMedic: nothing reaches the cloud model uncleaned.
// Every tool's result (read, bash, …) passes through sysmedic-redact on the laptop before OpenCode sends it, and the
// file tools can't open the customer's own folders (C:\Users, /home) unless the engineer recorded the customer's
// agreement (sysmedic-consent users). The shell has the same rules (/etc/sysmedic/audit.sh).
// OpenCode's read tool must stay available: Zen's free tier refuses requests without it.
import { spawnSync } from "node:child_process"
import { existsSync } from "node:fs"

const REDACT = "/usr/local/bin/sysmedic-redact"
const CONSENT = "/run/sysmedic/consent/users"
const USER_DIRS = /[\/\\](users|home)([\/\\]|$)/i

function clean(text) {
  if (typeof text !== "string" || !text || !existsSync(REDACT)) return text
  const r = spawnSync(REDACT, [], { input: text, encoding: "utf8", timeout: 60000, maxBuffer: 64 * 1024 * 1024 })
  // If cleaning fails, send nothing rather than the raw text
  return r.status === 0 && typeof r.stdout === "string" ? r.stdout : "[SysMedic: output withheld: it couldn't be cleaned]"
}

export const SysmedicClean = async () => ({
  "tool.execute.before": async (input, output) => {
    if (!["read", "grep", "glob", "list"].includes(input?.tool)) return
    const args = JSON.stringify(output?.args ?? {})
    if (USER_DIRS.test(args) && !existsSync(CONSENT)) {
      throw new Error("SysMedic: the customer's own folders (C:\\Users, /home) are closed to the AI without the customer's " +
        "explicit agreement. Ask the engineer: with the customer's OK they record it on the laptop (sysmedic-consent users).")
    }
  },
  "tool.execute.after": async (input, output) => {
    if (!output) return
    output.output = clean(output.output)
    if (typeof output.title === "string") output.title = clean(output.title).trim()
  },
})
