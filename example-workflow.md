# Example Workflow: What the AI Does Behind Each Request

This shows the exact tool calls the agent makes for a first week of operation, following `SKILL.md`. The owner only types the quoted lines; everything else is the agent's work. Assumes setup from `QUICKSTART.md` is complete (both MCP servers configured, `schema.sql` loaded, `SKILL.md` given as instructions).

IDs and responses are illustrative.

## Session start (every session)

```
sqlite_execute: PRAGMA foreign_keys = ON;
sqlite_query:   SELECT key, value FROM settings;
  → business_name = Green Lawn Mowing Co, timezone_offset = -05:00,
    default_worker_id = NULL, default_shift_start = 09:00, default_shift_minutes = 60,
    invoice_due_days = 14, invoice_prefix = INV
```

## "My business is Green Lawn Mowing Co in Springfield, IL, Central time."

```
sqlite_execute: UPDATE settings SET value = 'Green Lawn Mowing Co' WHERE key = 'business_name';
sqlite_execute: UPDATE settings SET value = '-05:00' WHERE key = 'timezone_offset';
```

> Saved. I'll schedule everything in Central time (-05:00).

## "Add a customer: Alice Green, alice@example.com, 555-0101, 123 Maple Street, Springfield IL 62701. $45 every two weeks, first cut 2026-09-02."

```
sqlite_execute:
  INSERT INTO customers (customer_name, contact_email, contact_phone, service_rate, service_frequency, next_service_date)
  VALUES ('Alice Green', 'alice@example.com', '555-0101', 45.00, 'biweekly', '2026-09-02');
  → lastInsertRowid = 1

sqlite_execute:
  INSERT INTO properties (customer_id, address, city, state, zip)
  VALUES (1, '123 Maple Street', 'Springfield', 'IL', '62701');
  → lastInsertRowid = 1
```

Agent (first metered call this session, rule 8):

> Creating Alice's location on ZenSched costs $0.05 for geocoding. If your account isn't funded yet you'll get a prompt for the $5 activation deposit. Go ahead?

Owner: *"yes"*

```
location_create:
  address: "123 Maple Street, Springfield, IL 62701"
  idempotency_key: "loc-property-1"
  → location_id: "loc_map123abc", lat: 39.7817, lng: -89.6501
    billing: { meter: "geocode", units: 1, price: 0.05 }

event_create:
  name: "Lawn Mowing - 123 Maple Street"
  location_id: "loc_map123abc"
  idempotency_key: "event-property-1"
  → event_id: "evt_maple1"

sqlite_execute:
  UPDATE properties SET zensched_location_id = 'loc_map123abc', zensched_event_id = 'evt_maple1'
  WHERE property_id = 1;
```

> Added Alice Green, 123 Maple St, $45 biweekly, first cut Tue 9/2.

## "Add Bob Turner, bob@example.com, 555-0202, 456 Oak Avenue, Springfield IL 62702, $55 weekly, first cut 2026-09-03."

Same pattern. The agent does not re-ask about the $0.05 (owner already approved geocoding this session).

```
sqlite_execute: INSERT INTO customers (...) VALUES ('Bob Turner', ..., 55.00, 'weekly', '2026-09-03');   → 2
sqlite_execute: INSERT INTO properties (customer_id, address, city, state, zip) VALUES (2, '456 Oak Avenue', ...);  → 2
location_create: address "456 Oak Avenue, Springfield, IL 62702", idempotency_key "loc-property-2"  → loc_oak456xyz
event_create:    name "Lawn Mowing - 456 Oak Avenue", location_id loc_oak456xyz, idempotency_key "event-property-2"  → evt_oak2
sqlite_execute:  UPDATE properties SET zensched_location_id = 'loc_oak456xyz', zensched_event_id = 'evt_oak2' WHERE property_id = 2;
```

## "Invite Mike at mike.worker@example.com and make him my default worker."

```
worker_invite:
  email: "mike.worker@example.com"
  name: "Mike"
  idempotency_key: "worker-mike.worker@example.com"
  → worker_id: "wrk_mike123", invitation_sent: true
    billing: { meter: "worker_invite", units: 1, price: 0.00 }

sqlite_execute: UPDATE settings SET value = 'wrk_mike123' WHERE key = 'default_worker_id';
```

> Invited Mike. He'll get an email with a link to install the ZenSched app. I've set him as the default worker for scheduling.

## "Schedule this week's lawns for Mike."

```
sqlite_query: SELECT * FROM customers_due;
  → 1 | Alice Green | ... | 2026-09-02 | property 1 | loc_map123abc | evt_maple1
    2 | Bob Turner  | ... | 2026-09-03 | property 2 | loc_oak456xyz | evt_oak2

shift_create:
  event_id: "evt_maple1"
  worker_id: "wrk_mike123"
  start_time: "2026-09-02T09:00:00-05:00"
  end_time:   "2026-09-02T10:00:00-05:00"
  idempotency_key: "shift-property-1-20260902"
  → shift_id: "shft_alice001", status: "scheduled"

shift_create:
  event_id: "evt_oak2"
  worker_id: "wrk_mike123"
  start_time: "2026-09-03T09:00:00-05:00"
  end_time:   "2026-09-03T10:00:00-05:00"
  idempotency_key: "shift-property-2-20260903"
  → shift_id: "shft_bob001", status: "scheduled"
```

> Scheduled 2 lawns for Mike this week: Alice Green, 123 Maple St (Tue 9/2 9:00–10:00) and Bob Turner, 456 Oak Ave (Wed 9/3 9:00–10:00). Mike's been notified in the app.

Nothing is written to SQLite here. If the owner asks "schedule this week" again, the identical idempotency keys make ZenSched return the same two shifts instead of creating duplicates.

## Mike does the work

In the ZenSched app: checks in at 123 Maple St (GPS verified), mows, takes a photo, checks out. Same at 456 Oak Ave the next day.

## "Record what Mike finished this week."

```
timesheet_export:
  mode: "hours"
  start_date: "2026-09-01"
  end_date: "2026-09-07"
  → workers: [ { worker_id: "wrk_mike123", shifts: [
        { shift_id: "shft_alice001", date: "2026-09-02", hours: 0.78 },
        { shift_id: "shft_bob001",   date: "2026-09-03", hours: 1.20 } ], total_hours: 1.98 } ]
    billing: { meter: "timesheet_export_hours", units: 0, price: 0.00 }

sqlite_query: SELECT zensched_shift_id FROM jobs WHERE zensched_shift_id IN ('shft_alice001', 'shft_bob001');
  → (none; not yet recorded)

sqlite_query: SELECT p.property_id, p.customer_id, c.service_rate FROM properties p JOIN customers c USING (customer_id) WHERE p.zensched_event_id = 'evt_maple1';
  → 1, 1, 45.00

sqlite_execute:
  INSERT INTO jobs (customer_id, property_id, completed_date, amount, zensched_shift_id, zensched_event_id, zensched_worker_id, duration_hours)
  VALUES (1, 1, '2026-09-02', 45.00, 'shft_alice001', 'evt_maple1', 'wrk_mike123', 0.78);

sqlite_execute:
  INSERT INTO jobs (customer_id, property_id, completed_date, amount, zensched_shift_id, zensched_event_id, zensched_worker_id, duration_hours)
  VALUES (2, 2, '2026-09-03', 55.00, 'shft_bob001', 'evt_oak2', 'wrk_mike123', 1.20);
```

The `advance_service_date_on_job` trigger fires on each insert. No `UPDATE customers` needed:

```
sqlite_query: SELECT customer_name, last_service_date, next_service_date FROM customers;
  → Alice Green | 2026-09-02 | 2026-09-16   (biweekly, +14)
    Bob Turner  | 2026-09-03 | 2026-09-10   (weekly, +7)
```

> Recorded 2 jobs: Alice (Tue, 47 min) and Bob (Wed, 1h 12m). Alice is next due Tue 9/16, Bob next Wed 9/10.

## "Draft invoices for everyone with uninvoiced work."

```
sqlite_query: SELECT * FROM jobs_to_invoice;
  → Alice Green | 1 job | 45.00
    Bob Turner  | 1 job | 55.00

sqlite_execute:
  INSERT INTO invoices (customer_id, invoice_date, due_date, total_amount, line_items)
  SELECT j.customer_id, date('now'),
         date('now', '+' || (SELECT value FROM settings WHERE key = 'invoice_due_days') || ' days'),
         SUM(j.amount),
         json_group_array(json_object('job_id', j.job_id, 'date', j.completed_date, 'amount', j.amount, 'shift_id', j.zensched_shift_id))
  FROM jobs j WHERE j.invoiced = 0 AND j.customer_id = 1 GROUP BY j.customer_id;

sqlite_execute: UPDATE jobs SET invoiced = 1 WHERE invoiced = 0 AND customer_id = 1;
sqlite_query:   SELECT invoice_number, invoice_date, due_date, total_amount FROM invoices WHERE customer_id = 1 ORDER BY invoice_id DESC LIMIT 1;
  → INV-2026-0001 | 2026-09-05 | 2026-09-19 | 45.00     (number assigned by trigger)

(same three statements for customer 2 → INV-2026-0002, 55.00)
```

The agent then writes the invoices out as text:

> Here are your two invoices. Paste each into an email.
>
> ```
> Green Lawn Mowing Co
> Invoice INV-2026-0001
> To: Alice Green (alice@example.com)
> Date: Sep 5, 2026    Due: Sep 19, 2026
>
>   Sep 2, 2026   Lawn mowing, 123 Maple Street        $45.00
>
> Total due: $45.00
> ```
>
> ```
> Green Lawn Mowing Co
> Invoice INV-2026-0002
> To: Bob Turner (bob@example.com)
> Date: Sep 5, 2026    Due: Sep 19, 2026
>
>   Sep 3, 2026   Lawn mowing, 456 Oak Avenue          $55.00
>
> Total due: $55.00
> ```
>
> Say "sent" when they're out and I'll note the date.

## "Sent. And Alice already paid."

```
sqlite_execute: UPDATE invoices SET sent_date = date('now') WHERE invoice_number IN ('INV-2026-0001', 'INV-2026-0002');
sqlite_execute: UPDATE invoices SET paid = 1, paid_date = date('now') WHERE invoice_number = 'INV-2026-0001';
```

> Marked both sent and INV-2026-0001 paid. Bob's $55 (INV-2026-0002) is outstanding, due Sep 19.

## "Who owes me money?"

```
sqlite_query: SELECT * FROM invoices_outstanding;
  → INV-2026-0002 | Bob Turner | due 2026-09-19 | 55.00 | overdue 0
```

> One open invoice: Bob Turner, $55, due Sep 19 (not overdue yet).

## Summary of who stored what

| Thing | Where | Why |
|---|---|---|
| Alice's address, rate, cadence, next due date | SQLite | CRM; ZenSched does not model pricing or recurrence |
| Alice's GPS location and "Lawn Mowing" event | ZenSched (IDs in SQLite) | Needed for shifts and geofenced check-in |
| Mike, his invite, his app | ZenSched (ID in `settings`) | Workforce and notifications |
| This week's two shifts | ZenSched only | Live schedule; never copied |
| GPS punches, actual hours | ZenSched only | Verified record; queried via `timesheet_export` |
| Two `jobs` rows referencing the shift IDs | SQLite | Billing needs a durable "this visit is billable" record |
| Two invoices, one paid | SQLite | Billing |
