# Roadmap: an easier SysMedic, a full GUI, and tutorials throughout

Status: **proposal for decision** (2026-11-11). Nothing here is built except what section 1 lists. It builds on [GUI-TOOLS](GUI-TOOLS.md) (the tool-by-tool plan, 2026-10-18) and reorders it around what people are trying to do. It does not replace the priorities in [ROADMAP](../ROADMAP.md): real-hardware validation, encryption of SysMedic's own storage, offline-model accuracy, networking and the safety controls come first, and every phase below says what it needs from them.

**How this was made:** from reading the repo (scripts, menus, dashboard, docs, the prototype in `tools/forms/`), not from watching anyone use SysMedic. Where a point is a guess about how people struggle, it is marked **(assumption)**, and Phase 0 exists to replace those with observations.

## 1. Where SysMedic is today

| Surface | What it is | Where it works | Gaps |
|---|---|---|---|
| **Consoles** (tty1 assistant, tty2 engineer) | Guided boot (vault, Wi-Fi, scan, consent), the AI assistant, the rescue menu (about 20 keys: digits and letters), every tool as a command | Everything: stick, Lite, caddy, no graphics needed | You must know what to ask or which key; no explanation of *why* a step matters |
| **Phone dashboard** (token and QR, port 8080) | Scan, tests, BitLocker unlock, notes, job report; the Control Centre | Any browser on the hotspot or LAN | Read-mostly by design (repairs from the phone are *Not planned*) |
| **Control Centre window and desktop** (menu G: labwc, waybar, fuzzel, Thunar, GNOME Disks, Mousepad) | The dashboard in a plain window plus a few apps | **Caddy only**; needs 4 GB RAM and a graphics device; labelled prototype | No desktop on the stick; no folders of tools yet |
| **SysMedic Forms** (`tools/forms/`) | Spec-driven GTK windows, desktop-folder builder, 35 app launchers, 5 starter specs | Not installed on any drive (kept out of `build/staging`) | Headless-checked only; never run on a booted SysMedic |
| **Help** | `sysmedic-help`: pick a Markdown guide, read it in `less` | Everywhere | No search, no pictures, no link from a finding to its guide |
| **Tutorials** | None. The field guide and docs are reference text | | The first-run guidance that exists (vault set-up, Wi-Fi first screen) is the part people like |

What already works in the users' favour, and must not be lost: the guided first screens (Wi-Fi, vault), the QR code to the phone, plain-English findings ordered by severity with a next step, read-only by default, and consoles that keep working when graphics don't.

## 2. What makes it hard to use (analysis)

1. **Three front doors with different powers, and a fourth coming.** The console, the phone, the desktop window and Forms each know a different subset of the tools. Without a shared model they will drift.
2. **The plan is tool-centric.** GUI-TOOLS gives about 100 console tools a window and ten desktop folders. That helps someone who knows *which tool*. It does not help someone who knows only *"this PC won't start"* **(assumption: this is the common case for the less experienced users GUI-TOOLS is written for)**.
3. **Discoverability.** The menu mixes digits and letters (`H`, `K`, `R`, `O`, `N`, `V`, `G`...), and the rest is behind the AI or `--help`.
4. **Help is a pager.** No search, no "what is this?" next to a finding, no way to go from a finding to the guide that explains it.
5. **No safe way to learn.** A new engineer's first BitLocker unlock or password reset is on a customer's machine **(assumption)**.
6. **Write protection is invisible and its failures are confusing.** A graphical app that tries to write to a protected disk just gets an error. People need to see the protection state and have one obvious, audited way to unlock for repair.
7. **Destructive actions confirm in different ways** (`sysmedic-confirm`, per-tool prompts); a GUI must not add more.
8. **The stick has no GUI at all**, and it is the edition people carry. Its limits are real: 8 GB, a Lite ISO that must stay under 1.5 GB (it is 1.1 GB now), 4 GB machines.
9. **No loop back from use.** The local review bundles record sessions, but nothing asks "was this step clear?". Telemetry is ruled out, so the loop has to be local and opt-in.

## 3. Principles

1. **Task first, tool second.** Lead with what the person is trying to do; the tools are the layer underneath for experts.
2. **One catalogue, many surfaces.** A task is described once, in data; the console menu, the Control Centre, Forms windows, the phone and the printed cards are all rendered from it.
3. **Every surface keeps the same safety.** The GUI never bypasses `sysmedic-guard`, the consent prompts or the engineer lock. Risk is shown the same way everywhere: **read-only / changes things / destroys data**.
4. **The console never goes away.** Graphics are optional, fail back to it, and nothing important is graphics-only (nomodeset, 4 GB RAM, no `/dev/dri`).
5. **Tutorials are part of the product, not a manual.** In the flow, skippable, offline, and one skill level at a time.
6. **Offline and private.** All assets on the drive (no CDN, no web fonts), no call-home, progress and preferences stored locally (in the vault where they could identify a customer), usability feedback only through the existing review bundles.
7. **Prove it on real hardware.** Anything that depends on the GPU goes in the hardware validation matrix before it is the default.

## 4. The design

### 4.1 One task catalogue

A task is a small data file (TOML or Markdown with front matter), the same idea as a Forms spec, extended:

- **id, title, plain-English summary, when to use it** ("The PC shows a black screen after the logo")
- **risk:** read-only, changes things, or destroys data; **needs:** engineer unlock, internet, a Windows disk, a vault
- **steps:** each is either *explain* (text, with an optional "why"), *run* (a command or tool, with the Forms fields), *check* (what good looks like, evaluated by a script where possible) or *decide* (branch on a finding)
- **glossary links** and the **doc section** it belongs to
- **practice:** the synthetic patient it can be rehearsed on (4.4)

From it: the console menu entry and a step-by-step console runner; the Control Centre page; the Forms window; a phone card (read-only steps only); a printable one-page card; and the AI assistant's context ("the engineer is on step 3 of *Recover deleted files*"). A **launcher test** fails the build if a tool or task has no catalogue entry or an explicit "not a tool" marker (the check GUI-TOOLS already asks for).

### 4.2 The Guided Visit

A single path through a visit, available on every surface, that the current boot flow already half provides:

1. **Welcome** (first boot of a drive only, 60 seconds, skippable): what this drive is, that customer disks are write-protected, the vault, consent. Never shown again unless asked.
2. **Intake:** customer, machine, what they report ("won't boot", "slow", "virus?", "lost files", "no internet", "just check it").
3. **Scan:** the existing triage, with each finding carrying *what it means*, *how worried to be*, and *what to do next* as buttons that start the matching task.
4. **Fix:** the task flows (section 5 lists the first ten).
5. **Verify:** re-scan or test, and show before and after.
6. **Report:** the customer report, plain language, ready to hand over (and, later, the exchange `EXPORT/` hand-back).

Experienced people skip straight to tools: **skill level** (Guided, Standard, Engineer) changes how much explanation and confirmation is shown, never what safety applies. It is stored on the drive and never reported anywhere.

### 4.3 The surfaces

| Surface | Role | Notes |
|---|---|---|
| **Console** | Always works; keyboard-first | A step runner for the catalogue; the menu gets grouped under tasks, with the letters kept as shortcuts; built first because it is the only surface on the stick today |
| **Control Centre (web UI)** | The main GUI | One web codebase served to the desktop window (WebKit), a laptop browser and the phone; reuses `sysmedic-dash`; destructive steps only offer a "do this on the SysMedic screen" hand-off unless the person is at the machine and passes the engineer unlock |
| **Forms** | Native windows for tools that need pickers and live output | Generated from the same catalogue entries; the long tail of tools; GTK to keep the image small |
| **Third-party apps** (Tier A: GParted, GSmartControl, Baobab...) | The expert long tail | Launched from the desktop folders and from a task step; wrapped by the write-protection indicator below |

**Decision, with a recommendation:** make the **Control Centre web UI the main GUI**, not a growing pile of GTK windows. One implementation then serves the caddy desktop, a laptop or phone on the private hotspot, and the stick: the stick can have a "full GUI" with **no on-stick desktop** by opening the Control Centre from the engineer's own laptop or phone (the hotspot and QR already exist), which suits the 8 GB and Lite limits. Forms stays for what a browser should not do (disk pickers needing local devices, live tools). See section 7, D1 and D2.

**Write-protection made visible:** a persistent indicator (panel and web header) showing "customer disks are write-protected" and a single **Unlock for repair** button that runs the existing engineer unlock (with the backup it already takes and an audit entry), and that third-party apps launched under the desktop explain when a write is blocked, instead of showing a raw error.

### 4.4 Tutorials, in layers

1. **Welcome tour**, once per drive (4.2).
2. **Inline explanations:** every finding and every step has "What is this?" and "Why?" text, written once, in the catalogue and the glossary, shown on every surface. This is the cheapest and most used layer.
3. **Walkthroughs:** the catalogue steps *are* the tutorials. Two modes: **Show me** (explains and waits) and **Do it with me** (runs the safe steps, stops at each risky one).
4. **Practice patients:** small synthetic disk images generated on demand (the repo already builds a fake Windows tree and fixtures: `build/tests/make-windows-fixture.py`, `make-windows-tree.sh`), attached as a **loop device that is not the customer's disk**, with a clear "PRACTICE" banner. A trainee rehearses BitLocker unlock, password clearing, undelete and imaging with no real risk. Practice sessions never enter a customer's job report.
5. **Search and context help:** `sysmedic-help` becomes searchable HTML in the Control Centre (and keeps the `less` view on the console); F1 or `?` opens help for the current screen or step.
6. **AI as tutor:** the assistant is given the current task and step, and "Explain this" and "Why did it say that?" use it. This depends on the offline-model accuracy work (ROADMAP item 5); until then the written explanations are the source of truth and the AI is optional.
7. **Field cards:** one-page printable cards (PDF) generated from the catalogue for the ten core tasks.

### 4.5 Learning from use, without telemetry

- A **"this was confusing"** key and button on every step, which calls the existing `sysmedic-note --feedback` with the task and step id. It lands in the review bundle that already exists, stays local, and is read by a person.
- **Observed sessions** (Phase 0 and after each phase): watch three to five people do the core tasks, and note where they stop. This is the real test of "easier".
- Local, aggregate-free numbers only: the review bundles can show time to first finding and which steps were skipped, for a person to read.

## 5. The first ten tasks (proposed, to confirm in Phase 0)

Chosen as the likely common visits **(assumption: confirm against the transcripts and your own list)**:

1. Check a PC over and give the customer a report
2. A PC that won't start (boot repair diagnosis)
3. Is the disk failing? (SMART, copy a failing disk safely)
4. Recover deleted or lost files
5. Windows password forgotten or account locked
6. BitLocker locked out
7. Slow computer (hardware tests, startup, malware)
8. Virus or malware check
9. No internet or Wi-Fi problems
10. Import a Windows snapshot from the customer's machine (the exchange partition: [EXCHANGE](EXCHANGE.md))

## 6. Phases

Sizes are relative (S, M, L), not calendar time. Phases 0 and 1 are software-only and can run alongside the real-hardware validation priority; Phase 2 onward needs the hardware matrix.

### Phase 0: Decide and observe (S)
- Settle D1 to D6 (section 7).
- **Observe three to five real sessions** and read the existing session transcripts and review bundles for where people stall; confirm the ten tasks and the personas.
- Define the catalogue schema and the single risk vocabulary; unify `sysmedic-confirm` as the one confirmation component.
- Move `tools/forms/` into `build/staging` behind a flag (so a running deploy is not disturbed), with its unit tests added to the suite.
- **Exit:** a decision record, a ranked task list, a schema with two tasks written in it.

### Phase 1: The catalogue and the Guided Visit on the console (M)
- Catalogue loader, console step runner, menu grouped by task (letters kept), welcome tour, inline "What is this?/Why?" for every scan finding, glossary, searchable `sysmedic-help`, **write-protection status line and one-key unlock**.
- Works on stick, Lite and caddy; no new packages.
- Tests: schema and catalogue tests, launcher test, console flows driven through a pty (the pattern in `test_exchange.py`), screenshot checks of the boot flow in QEMU (as done for the quiet-boot work).
- **Exit:** the first three tasks complete from the console by someone who has not used SysMedic, in an observed session.

### Phase 2: The Control Centre becomes the GUI (L)
- Control Centre pages rendered from the catalogue: Guided Visit, task flows, findings with actions, the write-protection indicator, tutorials overlay, help search, "this was confusing".
- Destructive steps stay on the local screen; the phone and a remote browser see everything and can run read-only steps and take notes.
- Accessibility baseline: keyboard-only use, large-text and high-contrast modes, minimum contrast checks.
- Tests: the dashboard's HTTP API tests, headless-browser or WebKit screenshot checks, keyboard-reachability checks.
- **Exit:** the ten tasks run end to end from the Control Centre on the caddy desktop, from a laptop browser on the stick's hotspot, and from the phone (read-only parts).

### Phase 3: Forms and the long tail (L)
- Forms windows for the tool-centric tasks that need them (PhotoRec/TestDisk, ddrescue, backup and restore, secure erase, Windows accounts and logs), driven by catalogue entries, behind the engineer lock where destructive.
- Tier A apps installed folder by folder, each checked to open on the live image; desktop folders at login.
- Hardware validation matrix for the desktop: Intel, AMD, NVIDIA and `nomodeset`, on real machines, with the console fallback proven.
- **Exit:** every tool has a catalogue entry or an explicit "not a tool" marker; no desktop path loses the console fallback.

### Phase 4: Practice patients and field cards (M)
- Synthetic patients (generated, small, clearly marked), a Practice mode in the Control Centre, "Show me" and "Do it with me" modes for every core task, printable cards.
- **Exit:** a new engineer rehearses the ten tasks without a customer, and the observed session in Phase 0 is repeated to measure the difference.

### Phase 5: The stick and the edges (M, depends on measurements)
- Measure (not estimate) the size and memory of an on-stick kiosk (a single-window compositor showing the Control Centre) against the 8 GB stick, the Lite ISO limit and 4 GB RAM machines; ship it only if it fits, otherwise keep "GUI from your own laptop or phone".
- Localisation (strings extracted; UK English first), the customer report's look, exchange `EXPORT/` hand-back, optional AI tutor once offline accuracy allows.

## 7. Decisions needed (with recommendations)

| | Question | Recommendation |
|---|---|---|
| **D1** | Is the web Control Centre the main GUI, or a GTK window per tool? | Control Centre as the main GUI; Forms only where a browser can't do the job |
| **D2** | Does the stick get an on-stick desktop? | Not yet: the stick's GUI is the Control Centre from a laptop or phone over the hotspot; revisit after Phase 5 measurements |
| **D3** | Who is "easier" for? | The less experienced engineer first (guided, practice); the customer-facing parts are the report and the plain-English findings |
| **D4** | Tutorial format and authoring | Markdown with front matter, in the repo, rendered by every surface; the AI may draft, a person reviews |
| **D5** | Languages | UK English now; extract strings in Phase 5 |
| **D6** | AI's role in tutorials | Optional explainer after the written explanations exist; never the only source |

## 8. Risks and how they are handled

| Risk | Handling |
|---|---|
| Scope: about 100 tools | Task-first order; the catalogue and launcher test make the long tail incremental; Tier A is "install and launch", not "build" |
| Surfaces drift apart | One catalogue; tests render every task on every surface |
| A GUI weakens safety | The GUI calls the same guard, consent and confirm components; destructive steps are local-only and engineer-locked; tests assert no GUI path writes without them |
| Graphics fail on real hardware | Console fallback is a hard requirement; hardware matrix before default; `nomodeset` tested |
| Size and memory | Budgets in CI (image size, idle RAM); Lite stays console plus phone; stick measured first |
| Tutorials go stale | They are the steps themselves, tested against the practice patients |
| Competing with the existing priorities | Phases 0 and 1 are software-only; Phase 2 starts after the hardware validation pass in ROADMAP items 1 and 2 |
| Third-party apps confuse the write protection | The indicator, plain "this disk is protected" messages and the one unlock path (4.3) |

## 9. How we will know it is easier

- **Observed:** a first-time user completes the first five tasks unaided (target to set in Phase 0, then re-measured after Phases 1, 2 and 4).
- **Local records:** fewer "confusing" notes per visit, and a falling share of visits that need the AI for something a catalogue step covers.
- **Quality gates:** launcher test, task rendering tests, keyboard-only checks, QEMU screenshot checks, and the real-hardware matrix, all green before a phase is called done.
