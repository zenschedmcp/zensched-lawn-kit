-- ZenSched Lawn Company Local Database Schema
-- SQLite database for CRM and billing only.
-- DO NOT duplicate live schedule data from ZenSched (shifts, punches, timesheets).
--
-- HOW TO LOAD THIS FILE
--   Normal path: paste this whole file into your AI chat and say
--   "Create these tables in my lawn-ops database. Run each statement one at a time."
--   The AI runs each statement through the SQLite MCP tool (sqlite_execute).
--   Most SQLite MCP tools accept ONE statement per call, so every statement
--   below ends with a semicolon and stands alone.
--
--   Alternative (if you have the sqlite3 command-line tool):
--     sqlite3 lawn-ops.db < schema.sql
--
-- Every statement is idempotent (IF NOT EXISTS / INSERT OR IGNORE), so it is
-- safe to run this file again on an existing database.

-- Foreign keys are OFF by default in SQLite. This must be run once per
-- connection for ON DELETE CASCADE to work. SKILL.md tells the agent to run it
-- at the start of each session.
PRAGMA foreign_keys = ON;

-- Settings: small key/value store so the agent does not have to be re-told the
-- basics every session (timezone, default worker, business name).
CREATE TABLE IF NOT EXISTS settings (
  key TEXT PRIMARY KEY,
  value TEXT
);

INSERT OR IGNORE INTO settings (key, value) VALUES ('business_name', 'My Lawn Co');
INSERT OR IGNORE INTO settings (key, value) VALUES ('timezone_offset', '-05:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_worker_id', NULL);
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_start', '09:00');
INSERT OR IGNORE INTO settings (key, value) VALUES ('default_shift_minutes', '60');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_due_days', '14');
INSERT OR IGNORE INTO settings (key, value) VALUES ('invoice_prefix', 'INV');

-- Customers: contact information and service cadence
CREATE TABLE IF NOT EXISTS customers (
  customer_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_name TEXT NOT NULL,
  contact_email TEXT,
  contact_phone TEXT,
  service_rate REAL NOT NULL,                       -- price per visit in dollars
  service_frequency TEXT NOT NULL
    CHECK (service_frequency IN ('weekly', 'biweekly', 'monthly', 'on-demand')),
  next_service_date TEXT,                           -- ISO 8601 date: '2026-09-01'
  last_service_date TEXT,                           -- set automatically when a job is recorded
  is_active INTEGER DEFAULT 1,                      -- 1 = active, 0 = inactive
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Properties: lawn locations with ZenSched references.
-- One ZenSched location AND one ZenSched event ("Lawn Mowing - <address>")
-- per property. The event is a reusable job template; each visit is a shift
-- on that event. Never create a new event per visit.
CREATE TABLE IF NOT EXISTS properties (
  property_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  address TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT,
  state TEXT,
  zip TEXT,
  zensched_location_id TEXT,                        -- loc_... from location_create
  zensched_event_id TEXT,                           -- evt_... from event_create (one per property, reused)
  square_feet INTEGER,
  terrain_notes TEXT,                               -- 'steep hill', 'many trees', 'easy flat lot'
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
);

-- Jobs: completed work records linked to ZenSched shifts
CREATE TABLE IF NOT EXISTS jobs (
  job_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  property_id INTEGER NOT NULL,
  completed_date TEXT NOT NULL,                     -- ISO 8601 date: '2026-08-30'
  amount REAL NOT NULL,
  zensched_shift_id TEXT UNIQUE,                    -- shft_... prevents recording the same shift twice
  zensched_event_id TEXT,                           -- evt_... reference
  zensched_worker_id TEXT,                          -- wrk_... reference
  duration_hours REAL,                              -- pulled from timesheet_export
  notes TEXT,                                       -- worker comments, issues encountered
  invoiced INTEGER DEFAULT 0,                       -- 1 = included in an invoice, 0 = pending
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE
);

-- Invoices: billing records.
-- invoice_number is filled in automatically by a trigger if left NULL.
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE,                       -- human-readable: 'INV-2026-0001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0,                           -- 1 = paid, 0 = unpaid
  paid_date TEXT,
  sent_date TEXT,                                   -- when you actually emailed/handed it over
  line_items TEXT,                                  -- JSON array of job references
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
);

-- Indexes for common queries
CREATE INDEX IF NOT EXISTS idx_customers_next_service ON customers(next_service_date, is_active);
CREATE INDEX IF NOT EXISTS idx_properties_customer ON properties(customer_id);
CREATE INDEX IF NOT EXISTS idx_properties_zensched_location ON properties(zensched_location_id);
CREATE INDEX IF NOT EXISTS idx_jobs_customer ON jobs(customer_id);
CREATE INDEX IF NOT EXISTS idx_jobs_invoiced ON jobs(invoiced);
CREATE INDEX IF NOT EXISTS idx_invoices_customer ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_paid ON invoices(paid);

-- Keep customers.updated_at current
CREATE TRIGGER IF NOT EXISTS update_customer_timestamp
AFTER UPDATE ON customers
BEGIN
  UPDATE customers SET updated_at = datetime('now') WHERE customer_id = NEW.customer_id;
END;

-- Recording a completed job automatically advances the customer's cadence.
-- The agent should NOT hand-maintain next_service_date after this.
CREATE TRIGGER IF NOT EXISTS advance_service_date_on_job
AFTER INSERT ON jobs
BEGIN
  UPDATE customers
  SET last_service_date = NEW.completed_date,
      next_service_date = CASE service_frequency
        WHEN 'weekly'   THEN date(NEW.completed_date, '+7 days')
        WHEN 'biweekly' THEN date(NEW.completed_date, '+14 days')
        WHEN 'monthly'  THEN date(NEW.completed_date, '+1 month')
        ELSE NULL                                    -- on-demand: no automatic next visit
      END
  WHERE customer_id = NEW.customer_id;
END;

-- Auto-number invoices: INV-2026-0001, INV-2026-0002, ...
CREATE TRIGGER IF NOT EXISTS number_invoice
AFTER INSERT ON invoices
WHEN NEW.invoice_number IS NULL
BEGIN
  UPDATE invoices
  SET invoice_number = (SELECT COALESCE(value, 'INV') FROM settings WHERE key = 'invoice_prefix')
                       || '-' || strftime('%Y', NEW.invoice_date)
                       || '-' || printf('%04d', NEW.invoice_id)
  WHERE invoice_id = NEW.invoice_id;
END;

-- Who is due in the next 7 days. The agent's weekly scheduling query.
CREATE VIEW IF NOT EXISTS customers_due AS
SELECT
  c.customer_id,
  c.customer_name,
  c.contact_email,
  c.contact_phone,
  c.service_rate,
  c.service_frequency,
  c.next_service_date,
  p.property_id,
  p.address,
  p.city,
  p.state,
  p.zip,
  p.zensched_location_id,
  p.zensched_event_id,
  p.terrain_notes
FROM customers c
JOIN properties p ON p.customer_id = c.customer_id
WHERE c.is_active = 1
  AND c.next_service_date IS NOT NULL
  AND c.next_service_date <= date('now', '+7 days')
ORDER BY c.next_service_date, c.customer_name;

-- Completed work that has not been invoiced yet, grouped by customer.
CREATE VIEW IF NOT EXISTS jobs_to_invoice AS
SELECT
  c.customer_id,
  c.customer_name,
  c.contact_email,
  COUNT(j.job_id)  AS job_count,
  SUM(j.amount)    AS total_amount,
  MIN(j.completed_date) AS first_job_date,
  MAX(j.completed_date) AS last_job_date
FROM jobs j
JOIN customers c ON c.customer_id = j.customer_id
WHERE j.invoiced = 0
GROUP BY c.customer_id
ORDER BY c.customer_name;

-- Unpaid invoices, oldest first.
CREATE VIEW IF NOT EXISTS invoices_outstanding AS
SELECT
  i.invoice_id,
  i.invoice_number,
  c.customer_name,
  c.contact_email,
  i.invoice_date,
  i.due_date,
  i.total_amount,
  i.sent_date,
  CASE WHEN i.due_date < date('now') THEN 1 ELSE 0 END AS overdue
FROM invoices i
JOIN customers c ON c.customer_id = i.customer_id
WHERE i.paid = 0
ORDER BY i.due_date;
