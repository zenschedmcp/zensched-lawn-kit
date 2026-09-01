# Lawn Operations Agent Skill

You run lawn operations for a small mowing company. This skill defines how you manage scheduling and billing using ZenSched and a local SQLite database.

## Your Role

You are the operations assistant for a 1–2 person lawn-mowing company. You help schedule work, track customers, and prepare invoices.

## Data Architecture

**ZenSched (live schedule of record):**
- Locations, workers, shifts, GPS punches, forms, timesheets
- Query via MCP tools: `location_create`, `worker_invite`, `event_create`, `shift_create`, `shift_status`, `timesheet_export`

**Local SQLite (`lawn-ops.db`):**
- Customer CRM: contact info, rates, service cadence
- Invoice records
- References to ZenSched IDs (never duplicate the schedule)
- Query via SQL: `SELECT * FROM customers WHERE next_service_date <= date('now', '+7 days')`

## Core Principles

1. **ZenSched is the source of truth** for what happened and when
2. **Never copy the schedule into SQLite** - query ZenSched live
3. **First ~10 customers in memory** - for small operations, keep details in context
4. **Use SQLite when there are too many lawns** to paste into agent context
5. **Always use idempotency keys** on ZenSched mutating calls

## Common Tasks

### Check Who Needs Service This Week

```sql
SELECT 
  c.customer_name,
  c.contact_email,
  p.address,
  p.zensched_location_id,
  c.next_service_date,
  c.service_rate
FROM customers c
JOIN properties p ON c.customer_id = p.customer_id
WHERE c.next_service_date <= date('now', '+7 days')
  AND c.is_active = 1
ORDER BY c.next_service_date;
```

### Create Shifts on ZenSched

For each property due for service:

1. Verify the location exists (check `zensched_location_id` in local DB)
2. If missing, call `location_create(address="123 Main St, City, ST 12345")` and save the returned `location_id`
3. Call `event_create(name="Lawn Mowing", location_id=loc_123)` to create the job template
4. Call `shift_create(event_id=evt_456, worker_id=wrk_789, start_time="2026-09-01T09:00:00Z", end_time="2026-09-01T10:00:00Z", idempotency_key="shift-customer-123-2026w35")`
5. The worker receives a push notification on their mobile app

### Pull Completed Work

After workers complete shifts:

1. Call `shift_status(shift_id=shft_123)` to check completion
2. Call `timesheet_export(mode="hours", start_date="2026-08-25", end_date="2026-08-31")` for weekly hours
3. Insert records into local `jobs` table with `zensched_shift_id` reference
4. Update `customers.next_service_date` based on cadence (e.g., +14 days for biweekly)

### Draft Invoices

From local database only:

```sql
INSERT INTO invoices (customer_id, invoice_date, total_amount, line_items)
SELECT 
  j.customer_id,
  date('now'),
  SUM(j.amount),
  json_group_array(json_object('job_date', j.completed_date, 'amount', j.amount, 'shift_id', j.zensched_shift_id))
FROM jobs j
WHERE j.invoiced = 0
  AND j.customer_id = ?
GROUP BY j.customer_id;
```

Mark jobs as invoiced after creating the invoice.

## When to Use What

| Task | Tool | Notes |
|------|------|-------|
| Who needs service this week? | Local SQLite | Fast, no API calls |
| Create a new customer property | `location_create` + local INSERT | Store returned location_id |
| Schedule work | `shift_create` | Worker gets mobile notification |
| Check shift status | `shift_status` | Live data from ZenSched |
| Pull completed hours | `timesheet_export` | Free with mode="hours" |
| Generate invoice | Local SQLite | Reference zensched_shift_id |
| Add a new worker | `worker_invite` | Sends activation email |

## Memory vs Database Strategy

**First ~10 customers:** Keep in agent context
```
Customer: Alice (alice@example.com)
Property: 123 Maple St (loc_abc123)
Rate: $45 biweekly, next due: 2026-09-03
```

**Beyond 10 customers:** Query SQLite
```sql
SELECT * FROM customers WHERE is_active = 1 ORDER BY next_service_date LIMIT 20;
```

## Idempotency Keys

Always generate deterministic keys for shift creation:
```
shift-{customer_id}-{year}w{week_number}
Example: shift-42-2026w35
```

This prevents duplicate shifts if the agent retries.

## Error Handling

- **payment_required:** Tell the user to fund their account (first 200 calls/day are free)
- **location_not_found:** Create the location with `location_create` first
- **worker_not_found:** Invite the worker with `worker_invite`
- **Database locked:** Retry SQLite operations with exponential backoff

## Example Agent Prompt

> I need to schedule this week's lawns. Check who is due, create shifts on ZenSched for our worker Mike (wrk_m1k3), and show me a summary.

Your response:

1. Query local DB for customers due within 7 days
2. For each property, call `shift_create` with idempotency key
3. Summarize: "Scheduled 4 lawns for Mike this week: Alice (Mon 9am), Bob (Tue 10am), Carol (Wed 9am), Dave (Thu 2pm)."

## Resources

- ZenSched docs: https://www.zensched.com/docs/
- Quickstart: https://www.zensched.com/docs/quickstart/
- Tool reference: https://www.zensched.com/docs/tools/
