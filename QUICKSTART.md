# Quickstart

Setup is about 15 minutes, once. After that everything is plain English to your AI. Each step below tells you what to do and, where relevant, exactly what to type to the AI.

You need: Claude Desktop (or Cursor) and [Node.js LTS](https://nodejs.org/) installed. Nothing else.

## 1. Make a data folder

Create a folder such as `C:\Users\YourName\lawn-ops` (Windows) or `/Users/yourname/lawn-ops` (Mac). Note the full path.

## 2. Add the two tools to your AI's config

Open the config file:

- **Claude Desktop, Windows:** `%APPDATA%\Claude\claude_desktop_config.json`
- **Claude Desktop, Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`
- **Cursor:** Settings → MCP → Add new global MCP server

Paste this in and fix only the `SQLITE_PATH` line to match your folder from step 1:

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

- On Windows, double every backslash: `"C:\\Users\\YourName\\lawn-ops\\lawn-ops.db"`.
- Leave `zsc_your_key_here` as it is. You get the real key in the next step.

Save, then **fully quit and reopen** the AI app.

## 3. Create your ZenSched account

Type to the AI:

> Call zensched_guide, then account_create with org_name "My Lawn Co". Show me the zsc_ key.

Copy the key into the config file in place of `zsc_your_key_here`. Save. Quit and reopen the app once more. (You can also ask the AI to call `account_use_key` with the key to continue right away, but update the file anyway so it sticks.)

## 4. Create the database tables

Copy the full contents of `schema.sql` and paste it into the chat with this line above it:

> Create these tables in my lawn-ops database. Run each statement one at a time with the SQLite tool, then list the tables to confirm.

## 5. Give the AI its instructions

Paste `SKILL.md` into the AI as standing instructions (Claude Desktop: a Project's instructions; Cursor: a rule). Then:

> My business is Green Lawn Mowing Co in Springfield, IL, Central time. Save that to settings.

## 6. Add your first customer

> Add a customer: Alice Green, alice@example.com, 555-0101, 123 Maple Street, Springfield IL 62701. $45 per cut, every two weeks, first cut on 2026-09-10.

Behind the scenes the AI inserts the customer, calls `location_create` (geocode, $0.05, may trigger the $5 activation deposit the first time), calls `event_create` once for the property, and saves both IDs. You just see a confirmation.

## 7. Invite your worker

> Invite Mike at mike@example.com as a worker and make him my default.

Mike gets an email, installs the app ([Android](https://play.google.com/store/apps/details?id=com.zensched.app) / [App Store](https://apps.apple.com/us/app/zensched/id6800081657)), and activates.

## 8. Schedule the week

> Schedule this week's lawns for Mike, starting at 9 am each day.

The AI checks who is due, creates one shift per property on ZenSched, and summarizes. Mike gets a push notification for each.

## 9. After the work is done

> Record the jobs Mike finished this week, then draft invoices for anyone with uninvoiced work.

The AI pulls completion from ZenSched, records each job (which automatically sets the next service date), creates invoice records, and writes out each invoice as text you can paste into an email.

> Alice paid INV-2026-0001.

Marks it paid.

## What next

- `README.md` for the full explanation, troubleshooting table, and developer notes
- `example-workflow.md` to see the exact tool calls behind each step above