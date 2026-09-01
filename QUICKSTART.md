# Quickstart

Get up and running in 5 minutes.

## 1. Get Your ZenSched Key

In your AI tool (Claude, Cursor, etc.), run:

```
zensched_guide
account_create(org_name="My Lawn Co")
```

Save the returned `zsc_` key.

## 2. Add MCP Server

**Claude Desktop — Windows:** `%APPDATA%\Claude\claude_desktop_config.json`

**Claude Desktop — Mac:** `~/Library/Application Support/Claude/claude_desktop_config.json`

```json
{
  "mcpServers": {
    "zensched": {
      "url": "https://mcp.zensched.com/mcp",
      "headers": { "Authorization": "Bearer zsc_your_key_here" }
    }
  }
}
```

**Cursor (Windows & Mac):** Settings → MCP Servers → same config.

Restart your AI tool.

## 3. Initialize Database

```bash
sqlite3 lawn-ops.db < schema.sql
```

## 4. Add Your First Customer

```sql
INSERT INTO customers (customer_name, contact_email, service_rate, service_frequency, next_service_date)
VALUES ('John Doe', 'john@example.com', 45.00, 'biweekly', '2026-09-10');
```

Then create the location in ZenSched:

```
location_create(address="123 Main St, City, ST 12345", idempotency_key="loc-john-1")
```

Save the returned `location_id` in your properties table.

## 5. Invite a Worker

```
worker_invite(email="worker@example.com", name="Mike", idempotency_key="worker-1")
```

They'll download the mobile app and activate.

## 6. Schedule a Job

```
event_create(name="Lawn Mowing", location_id="loc_abc123", idempotency_key="evt-1")
shift_create(
  event_id="evt_abc123",
  worker_id="wrk_xyz789",
  start_time="2026-09-10T09:00:00-05:00",
  end_time="2026-09-10T10:00:00-05:00",
  idempotency_key="shift-john-2026w37"
)
```

Worker gets a push notification. Done!

## Next Steps

- Read `README.md` for full Windows & Mac setup
- Check `SKILL.md` for agent prompts
- Review `example-workflow.md` for complete workflow

## Mobile Apps

- Android: [Google Play](https://play.google.com/store/apps/details?id=com.zensched.app)
- iOS: [TestFlight](https://testflight.apple.com/join/Wp51m5Yq)
