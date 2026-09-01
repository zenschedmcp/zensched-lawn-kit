# Example ZenSched Lawn Operations Workflow

This document shows a complete tool-loop example: creating an organization, adding properties, inviting a worker, scheduling jobs, pulling timesheets, and drafting invoices.

## Initial Setup

### 1. Get Your ZenSched Key

```
Tool: zensched_guide
Result: Returns current onboarding instructions
```

```
Tool: account_create
Parameters:
  org_name: "Green Lawn Mowing Co"
Result:
  api_key: "zsc_1a2b3c4d5e6f..."
  org_id: "org_abc123"
```

**Action:** Save the `zsc_` key and add it to your MCP configuration. Restart your AI tool.

### 2. Initialize Local Database

```bash
sqlite3 lawn-ops.db < schema.sql
```

## Adding Customer Properties

### Customer 1: Alice Green

```sql
INSERT INTO customers (customer_name, contact_email, contact_phone, service_rate, service_frequency, next_service_date)
VALUES ('Alice Green', 'alice@example.com', '555-0101', 45.00, 'biweekly', '2026-09-02');
```

```
Tool: location_create
Parameters:
  address: "123 Maple Street, Springfield, IL 62701"
  idempotency_key: "loc-alice-maple-123"
Result:
  location_id: "loc_map123abc"
  lat: 39.7817
  lng: -89.6501
  billing: { meter: "geocode", units: 1, price: 0.05 }
```

```sql
INSERT INTO properties (customer_id, address, city, state, zip, zensched_location_id)
VALUES (1, '123 Maple Street', 'Springfield', 'IL', '62701', 'loc_map123abc');
```

### Customer 2: Bob Turner

```sql
INSERT INTO customers (customer_name, contact_email, contact_phone, service_rate, service_frequency, next_service_date)
VALUES ('Bob Turner', 'bob@example.com', '555-0202', 55.00, 'weekly', '2026-09-03');
```

```
Tool: location_create
Parameters:
  address: "456 Oak Avenue, Springfield, IL 62702"
  idempotency_key: "loc-bob-oak-456"
Result:
  location_id: "loc_oak456xyz"
  lat: 39.7995
  lng: -89.6440
  billing: { meter: "geocode", units: 1, price: 0.05 }
```

```sql
INSERT INTO properties (customer_id, address, city, state, zip, zensched_location_id)
VALUES (2, '456 Oak Avenue', 'Springfield', 'IL', '62702', 'loc_oak456xyz');
```

## Adding a Worker

```
Tool: worker_invite
Parameters:
  email: "mike.worker@example.com"
  name: "Mike"
  idempotency_key: "worker-mike-001"
Result:
  worker_id: "wrk_mike123"
  invitation_sent: true
  billing: { meter: "worker_invite", units: 1, price: 0.00 }  # First invite may be free
```

**Worker action:** Mike receives an email, downloads the ZenSched mobile app (Android or iOS TestFlight), and activates his account.

## Scheduling This Week's Jobs

### Check Who is Due

```sql
SELECT 
  c.customer_id,
  c.customer_name,
  p.property_id,
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

**Result:**
- Alice Green: 123 Maple St, due 2026-09-02, $45
- Bob Turner: 456 Oak Ave, due 2026-09-03, $55

### Create Events and Shifts

#### Alice's Lawn (Monday 9am)

```
Tool: event_create
Parameters:
  name: "Lawn Mowing - Alice Green"
  location_id: "loc_map123abc"
  idempotency_key: "event-alice-20260902"
Result:
  event_id: "evt_alice123"
```

```
Tool: shift_create
Parameters:
  event_id: "evt_alice123"
  worker_id: "wrk_mike123"
  start_time: "2026-09-02T09:00:00-05:00"
  end_time: "2026-09-02T10:00:00-05:00"
  idempotency_key: "shift-1-2026w36"
Result:
  shift_id: "shft_alice001"
  status: "scheduled"
```

**Worker notification:** Mike receives a push notification on his mobile app.

#### Bob's Lawn (Wednesday 10am)

```
Tool: event_create
Parameters:
  name: "Lawn Mowing - Bob Turner"
  location_id: "loc_oak456xyz"
  idempotency_key: "event-bob-20260903"
Result:
  event_id: "evt_bob123"
```

```
Tool: shift_create
Parameters:
  event_id: "evt_bob123"
  worker_id: "wrk_mike123"
  start_time: "2026-09-03T10:00:00-05:00"
  end_time: "2026-09-03T11:00:00-05:00"
  idempotency_key: "shift-2-2026w36"
Result:
  shift_id: "shft_bob001"
  status: "scheduled"
```

## Worker Completes the Jobs

Mike uses the ZenSched mobile app to:
1. Check in when arriving at 123 Maple St (GPS verified)
2. Complete the work, take a photo
3. Check out
4. Repeat for 456 Oak Ave

## Pulling Timesheets

### Check Shift Status

```
Tool: shift_status
Parameters:
  shift_id: "shft_alice001"
Result:
  status: "completed"
  actual_start: "2026-09-02T09:05:00Z"
  actual_end: "2026-09-02T09:52:00Z"
  duration_hours: 0.78
```

```
Tool: shift_status
Parameters:
  shift_id: "shft_bob001"
Result:
  status: "completed"
  actual_start: "2026-09-03T10:03:00Z"
  actual_end: "2026-09-03T11:15:00Z"
  duration_hours: 1.20
```

### Export Weekly Timesheet

```
Tool: timesheet_export
Parameters:
  mode: "hours"
  start_date: "2026-09-01"
  end_date: "2026-09-07"
Result:
  workers:
    - worker_id: "wrk_mike123"
      name: "Mike"
      shifts:
        - shift_id: "shft_alice001"
          date: "2026-09-02"
          hours: 0.78
        - shift_id: "shft_bob001"
          date: "2026-09-03"
          hours: 1.20
      total_hours: 1.98
  billing: { meter: "timesheet_export_hours", units: 0, price: 0.00 }  # Free mode
```

## Recording Jobs Locally

```sql
INSERT INTO jobs (customer_id, property_id, completed_date, amount, zensched_shift_id, zensched_event_id, zensched_worker_id, duration_hours)
VALUES 
  (1, 1, '2026-09-02', 45.00, 'shft_alice001', 'evt_alice123', 'wrk_mike123', 0.78),
  (2, 2, '2026-09-03', 55.00, 'shft_bob001', 'evt_bob123', 'wrk_mike123', 1.20);
```

```sql
UPDATE customers SET next_service_date = date('2026-09-02', '+14 days') WHERE customer_id = 1;
UPDATE customers SET next_service_date = date('2026-09-03', '+7 days') WHERE customer_id = 2;
```

## Drafting Invoices

### Invoice for Alice (Biweekly Customer)

```sql
INSERT INTO invoices (customer_id, invoice_number, invoice_date, due_date, total_amount, line_items)
VALUES (
  1,
  'INV-2026-001',
  '2026-09-02',
  '2026-09-16',
  45.00,
  json_array(json_object('job_id', 1, 'date', '2026-09-02', 'amount', 45.00, 'shift_id', 'shft_alice001'))
);

UPDATE jobs SET invoiced = 1 WHERE job_id = 1;
```

### Invoice for Bob (Weekly Customer)

```sql
INSERT INTO invoices (customer_id, invoice_number, invoice_date, due_date, total_amount, line_items)
VALUES (
  2,
  'INV-2026-002',
  '2026-09-03',
  '2026-09-17',
  55.00,
  json_array(json_object('job_id', 2, 'date', '2026-09-03', 'amount', 55.00, 'shift_id', 'shft_bob001'))
);

UPDATE jobs SET invoiced = 1 WHERE job_id = 2;
```

## Summary

**Workflow Complete:**
- ✓ Created ZenSched organization
- ✓ Added 2 customer properties with geocoded locations
- ✓ Invited 1 worker
- ✓ Scheduled 2 shifts for this week
- ✓ Worker completed jobs via mobile app
- ✓ Pulled verified timesheets from ZenSched
- ✓ Recorded jobs in local database
- ✓ Generated 2 invoices

**Key Takeaway:** ZenSched handled all live scheduling, GPS verification, and time tracking. Local SQLite only stored CRM data and invoice records.
