# ZenSched Lawn Company Reference Kit

A copy-pasteable reference architecture for a 1–2 person lawn-mowing company using ZenSched for scheduling and a local SQLite database for CRM and billing.

## What Lives Where

**ZenSched (source of truth for operations):**
- Locations (customer properties with GPS coordinates)
- Workers (crew members with mobile app access)
- Events (job templates)
- Shifts (scheduled work with notifications)
- Forms (work verification, photos, notes)
- GPS punches (check-in/check-out with location verification)
- Timesheets (verified hours worked)

**Local SQLite (CRM and billing only):**
- Customer contact information
- Property-to-customer mapping
- Service rates and recurrence cadence
- Invoice records
- References to ZenSched IDs (location_id, worker_id, event_id, shift_id)

**Never duplicate:** Do not copy the live schedule, punches, or timesheets into SQLite. ZenSched is the source of truth for "what happened when."

## Windows Setup

### 1. Add the MCP Server to Your AI Tool

Copy `mcp.json.example` into your AI tool's MCP configuration:

**For Claude Desktop** (`%APPDATA%\Claude\claude_desktop_config.json`):
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

**For Cursor** (Settings → MCP Servers):
- Use the same configuration structure
- Or add via Cursor's MCP settings UI

### 2. Get Your ZenSched API Key

1. In your AI tool, call `zensched_guide` to verify the MCP connection
2. Call `account_create(org_name="YourLawnCompany")` with no email
3. Save the returned `zsc_` key securely
4. Update your MCP config with the real key and restart your AI tool

### 3. Initialize the Local Database

Copy `.env.example` to `.env` and add your API key:
```
ZENSCHED_API_KEY=zsc_your_actual_key_here
```

Initialize the SQLite database:
```bash
sqlite3 lawn-ops.db < schema.sql
```

Or on Windows:
```cmd
type schema.sql | sqlite3 lawn-ops.db
```

### 4. Fund Your Account (Optional)

The first 200 MCP calls per day are free. When you need metered operations (geocoding locations, inviting workers, refining pins, processed timesheets), you'll see a `payment_required` response with instructions. The $5 activation deposit is credited to your balance.

## Usage

### For AI Agents

See `SKILL.md` for a ready-to-use agent skill file. Key principles:

1. **Query local for who is due:** Check `lawn-ops.db` for customers with upcoming service cadence
2. **Create shifts on ZenSched:** Use ZenSched MCP tools to schedule work
3. **Never copy schedule into SQLite:** ZenSched holds the live week
4. **First ~10 customers in memory:** For small operations, keep customer details in context
5. **Use SQLite for many lawns:** When there are too many properties to paste into context

### Example Workflow

See `example-workflow.md` for a complete tool-loop example covering:
- Creating an organization
- Adding two customer properties
- Inviting a worker
- Scheduling this week's jobs from local cadence
- Pulling timesheets
- Drafting invoices locally

## Database Schema

Four simple tables (see `schema.sql`):
- `customers` - Contact info, rates, service frequency
- `properties` - Lawn addresses with ZenSched location_id references
- `jobs` - Completed work records with ZenSched shift_id references
- `invoices` - Billing records linked to jobs

## Best Practices

1. **Use idempotency keys:** Every ZenSched mutating call should include `idempotency_key` for safe retries
2. **Store ZenSched IDs:** Always save location_id, worker_id, event_id, shift_id in your local database
3. **Pull, don't push:** Query ZenSched for timesheet data; don't duplicate it locally
4. **Let workers use the app:** The ZenSched mobile app handles GPS punches, photos, and forms
5. **Start simple:** Use default brand 0 and policy 0 until you need custom branding

## Mobile App for Workers

- **Android:** [Google Play Store](https://play.google.com/store/apps/details?id=com.zensched.app)
- **iOS:** [TestFlight Beta](https://testflight.apple.com/join/Wp51m5Yq)

Workers download the app, receive an invitation email, and can immediately:
- See their scheduled shifts
- Check in/out with GPS verification
- Submit photos and notes
- Complete forms

## Support

- Documentation: https://www.zensched.com/docs/
- Submit feedback via the `feedback_submit` MCP tool (free, no auth required)
- Categories: `bug`, `friction`, `missing_capability`, `docs`, `billing`, `feature`, `other`

## License

MIT License - See LICENSE file
