# ZenSched Lawn Company Reference Kit

A copy-pasteable setup for a 1–2 person lawn-mowing company that wants an AI assistant to run scheduling, customer tracking, and invoicing. ZenSched handles the live schedule, GPS-verified check-ins, and timesheets. A small local database on your computer holds your customer list, rates, and invoices.

**You do not need to know how to program or write SQL to use this.** You type plain English to your AI assistant ("schedule this week's lawns", "add a new customer", "who owes me money?") and the AI does the work using two tools you set up once. Setup takes about 15 minutes and is the only technical part.

If you *are* a developer, skip to [For developers](#for-developers).

## What lives where

**ZenSched (source of truth for what happened, when):**

- Locations (customer properties with GPS coordinates)
- Workers (crew members with the mobile app)
- Events (one reusable "Lawn Mowing" job per property)
- Shifts (each scheduled visit, with push notifications to the worker)
- GPS punches (check-in/check-out with location verification)
- Timesheets (verified hours worked)

**Local SQLite database (`lawn-ops.db`, on your computer):**

- Customer contact info, price per visit, how often (weekly / biweekly / monthly)
- Which ZenSched location and event belong to which customer
- Completed jobs and invoices
- Your settings (timezone, default worker, invoice prefix)

**Never duplicated:** the live schedule, punches, and timesheets stay in ZenSched. The local database only stores *references* to them.

## How it works day to day

Your AI assistant has two sets of tools:

1. **ZenSched tools** (`location_create`, `shift_create`, `timesheet_export`, ...) that talk to ZenSched over the internet.
2. **A SQLite tool** (`sqlite_query`, `sqlite_execute`) that reads and writes `lawn-ops.db` on your computer.

When you say "schedule this week's lawns," the AI reads who is due from the local database, creates shifts on ZenSched, and tells you what it did. You never run SQL yourself. `SKILL.md` in this repo is the instruction sheet that teaches the AI how to do all of this; you paste it into your AI tool once.

## Setup

### 0. What you need

- **An AI tool that supports MCP.** These instructions use Claude Desktop (Windows or Mac). Cursor works too.
- **Node.js 20 or newer.** The SQLite tool runs on it. Download the LTS installer from [nodejs.org](https://nodejs.org/) and run it with the defaults. This is the only software install.
- You do **not** need the `sqlite3` command-line program, Python, or Git.

### 1. Make a folder for your data

Create a folder where the database will live and write down its full path. Examples:

- Windows: `C:\Users\YourName\lawn-ops`
- Mac: `/Users/yourname/lawn-ops`

The database file will be created automatically inside this folder the first time the AI uses it.

### 2. Add both tools to your AI's config file

Open the MCP configuration file for your AI tool:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json` (paste that into the File Explorer address bar)
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json` (in Claude Desktop: Settings → Developer → Edit Config)
- **Cursor:** Settings → MCP → Add new global MCP server

Paste in the contents of `mcp.json.example` from this repo, then change one line, the `SQLITE_PATH`, to point at your folder from step 1 plus `\lawn-ops.db` (Windows) or `/lawn-ops.db` (Mac):

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    },
    "lawn-ops-db": {
      "command": "npx",
      "args": ["-y", "easy-sqlite-mcp"],
      "env": { "SQLITE_PATH": "/Users/yourname/lawn-ops/lawn-ops.db" }
    }
  }
}
```

**Windows path gotcha:** inside a JSON file every backslash must be doubled. Write `"C:\\Users\\YourName\\lawn-ops\\lawn-ops.db"`, not `"C:\Users\..."`. A single backslash will silently break the config.

**Leave `zsc_your_key_here` exactly as it is for now.** You do not have a key yet. The ZenSched tools that create your account work without one, and you will fill this in during step 3.

Save the file and **fully quit and reopen** your AI tool (on Mac, Cmd-Q; on Windows, right-click the tray icon → Quit). It only reads this file on startup.

### 3. Create your ZenSched account

In a new chat, type:

> Call `zensched_guide`, then call `account_create` with org_name "My Lawn Co" (use my real company name if I told you one). Show me the `zsc_` key it returns.

Copy the `zsc_` key. Go back to the config file from step 2, replace `zsc_your_key_here` with your real key, save, and fully quit and reopen the AI tool again.

Some clients can adopt the key mid-session with `account_use_key`; you can ask the AI to try that to keep going immediately, but still update the config file so the key survives restarts. Keep the key private; it is the password to your account.

### 4. Create the database tables

Open `schema.sql` from this repo in any text editor, copy the whole thing, and paste it into the chat with this message in front of it:

> Create these tables in my lawn-ops database. Run each statement one at a time using the SQLite tool, then list the tables to confirm.

The AI will run about 26 statements and confirm the tables exist. The `lawn-ops.db` file now exists in your folder.

If you happen to have the `sqlite3` command-line tool, `sqlite3 lawn-ops.db < schema.sql` does the same thing, but it is not required.

### 5. Teach the AI the workflow

Paste the contents of `SKILL.md` into your AI tool as standing instructions. In Claude Desktop, create a Project and put it in the project instructions; in Cursor, save it as a rule. Then tell it your basics once:

> My business is Green Lawn Mowing Co in Springfield, IL (Central time). Save that in settings.

It writes those to the `settings` table so you do not have to repeat them.

### 6. Funding (only when asked)

The first 200 ZenSched tool calls per day are free. Creating a location (geocoding, $0.05) and inviting a worker are metered. When a metered call happens without funds, the AI will get a `payment_required` response and tell you how to add the $5 activation deposit, which is credited to your balance. You will not be charged without seeing this first.

## Using it

Everything after setup is plain English. Examples:

- "Add a customer: Alice Green, alice@example.com, 123 Maple Street, Springfield IL 62701, $45 every two weeks, first cut next Tuesday."
- "Invite my worker Mike at mike@example.com and make him the default."
- "Schedule this week's lawns for Mike, mornings starting at 9."
- "Which jobs got finished this week? Record them."
- "Draft invoices for everyone who has uninvoiced work."
- "Who still owes me money?"
- "Bob is pausing service for the summer."

See `QUICKSTART.md` for the first-week walkthrough and `example-workflow.md` for exactly which tools the AI calls behind each of these.

### What "invoice" means here

"Draft an invoice" records the invoice in your database (number, date, due date, amount, which jobs) and the AI writes out a plain-text invoice you can paste into an email or text message. It does **not** generate a PDF, email it for you, or collect payment. When the customer pays, tell the AI ("Alice paid INV-2026-0003") and it marks it paid. If you outgrow this, the invoice records are simple enough to import into any accounting tool.

## Mobile app for workers

- **Android:** [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [App Store](https://apps.apple.com/us/app/zensched/id6800081657)

When you invite a worker, they get an email, install the app, and can immediately see their shifts, check in and out with GPS verification, take photos, and complete forms.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| AI says it has no ZenSched tools | Config file not saved, or the app was not fully restarted | Check the JSON is valid (paste it into [jsonlint.com](https://jsonlint.com)), then quit and reopen the app |
| AI says it has no SQLite / `lawn-ops-db` tools | Node.js not installed, or bad `SQLITE_PATH` | Install Node.js LTS; on Windows check every backslash is doubled |
| `SQLITE_PATH` points nowhere / "unable to open database" | Folder from step 1 does not exist | Create the folder; the file is created automatically but the folder is not |
| ZenSched tools return an auth error | Key still says `zsc_your_key_here`, or was pasted with a space | Re-paste the key, restart |
| `payment_required` | Metered call with no balance | Follow the instructions in the response; $5 deposit |
| AI creates shifts at the wrong hour | Timezone not set | "Set my timezone offset to -05:00 in settings" (use your own offset) |
| AI asks you to run SQL yourself | It does not have `SKILL.md` loaded | Re-paste `SKILL.md` as project instructions |

If something is confusing or broken in ZenSched itself, ask the AI to call `feedback_submit` with a description. It is free, needs no account, and a human reads every submission.

## For developers

**Architecture.** Two MCP servers, no application code. The agent is the integration layer; `SKILL.md` is the spec it follows. ZenSched is authoritative for operations; SQLite is authoritative for CRM and billing; each side stores only the other's IDs.

**Data model decisions.**

- One ZenSched **location** and one ZenSched **event** per property, stored on `properties`. The event is a reusable job template; each visit is a `shift_create` against it. Do not create an event per visit.
- `customers.next_service_date` is **derived, not hand-maintained**: an `AFTER INSERT ON jobs` trigger advances it from `completed_date` by the customer's cadence. On-demand customers get `NULL`.
- `jobs.zensched_shift_id` is `UNIQUE` so a shift cannot be recorded twice.
- `invoices.invoice_number` is auto-assigned by trigger as `{prefix}-{YYYY}-{0001}`.
- `service_frequency` is `CHECK`-constrained to `weekly | biweekly | monthly | on-demand`.
- `PRAGMA foreign_keys = ON` is in `schema.sql` and `SKILL.md` tells the agent to run it per session; SQLite does not persist it.
- Views `customers_due`, `jobs_to_invoice`, `invoices_outstanding` exist so the agent's routine queries are one-liners it cannot get wrong.

**Idempotency keys.** Deterministic, derived from local IDs so a retried or re-run agent turn cannot duplicate:

- location: `loc-property-{property_id}`
- event: `event-property-{property_id}`
- shift: `shift-property-{property_id}-{YYYYMMDD}` (per visit date, so two visits in one week do not collide)
- worker: `worker-{email}`

ZenSched caches idempotent responses for 24 hours.

**Timestamps.** `shift_create` takes ISO 8601 with an explicit offset. Always use the business's local offset from `settings.timezone_offset` (e.g. `2026-09-02T09:00:00-05:00`), never `Z`.

**SQLite MCP server.** `mcp.json.example` uses [`easy-sqlite-mcp`](https://github.com/chenkumi/easy-sqlite-mcp) (Node, `better-sqlite3`, `SQLITE_PATH` env var). Its `sqlite_execute` calls `prepare()`, so it accepts **one statement per call**; `schema.sql` is written so every statement stands alone and is idempotent. Any SQLite MCP server with read and write tools will work; adjust the tool names in `SKILL.md`.

**Schema test.** The schema was verified by executing each statement individually (as the MCP server does) twice for idempotency, then exercising the CHECK, UNIQUE, cascade, both triggers, and all three views.

## Support

- ZenSched docs: <https://www.zensched.com/docs/>
- Tool reference: <https://www.zensched.com/docs/tools/>
- Feedback: ask your AI to call `feedback_submit` (categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`)

## License

MIT. See `LICENSE`.