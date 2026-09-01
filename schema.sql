-- ZenSched Lawn Company Local Database Schema
-- SQLite database for CRM and billing only
-- DO NOT duplicate live schedule data from ZenSched

-- Customers: contact information and service cadence
CREATE TABLE IF NOT EXISTS customers (
  customer_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_name TEXT NOT NULL,
  contact_email TEXT,
  contact_phone TEXT,
  service_rate REAL NOT NULL, -- price per visit in dollars
  service_frequency TEXT NOT NULL, -- 'weekly', 'biweekly', 'monthly', 'on-demand'
  next_service_date TEXT, -- ISO 8601 date: '2026-09-01'
  is_active INTEGER DEFAULT 1, -- 1 = active, 0 = inactive
  notes TEXT,
  created_at TEXT DEFAULT (datetime('now')),
  updated_at TEXT DEFAULT (datetime('now'))
);

-- Properties: lawn locations with ZenSched references
CREATE TABLE IF NOT EXISTS properties (
  property_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  address TEXT NOT NULL,
  address_line2 TEXT,
  city TEXT,
  state TEXT,
  zip TEXT,
  zensched_location_id TEXT, -- loc_... from location_create
  square_feet INTEGER,
  terrain_notes TEXT, -- 'steep hill', 'many trees', 'easy flat lot'
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE
);

-- Jobs: completed work records linked to ZenSched shifts
CREATE TABLE IF NOT EXISTS jobs (
  job_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  property_id INTEGER NOT NULL,
  completed_date TEXT NOT NULL, -- ISO 8601 date: '2026-08-30'
  amount REAL NOT NULL,
  zensched_shift_id TEXT, -- shft_... reference for traceability
  zensched_event_id TEXT, -- evt_... reference
  zensched_worker_id TEXT, -- wrk_... reference
  duration_hours REAL, -- pulled from timesheet_export
  notes TEXT, -- worker comments, issues encountered
  invoiced INTEGER DEFAULT 0, -- 1 = included in an invoice, 0 = pending
  created_at TEXT DEFAULT (datetime('now')),
  FOREIGN KEY (customer_id) REFERENCES customers(customer_id) ON DELETE CASCADE,
  FOREIGN KEY (property_id) REFERENCES properties(property_id) ON DELETE CASCADE
);

-- Invoices: billing records
CREATE TABLE IF NOT EXISTS invoices (
  invoice_id INTEGER PRIMARY KEY AUTOINCREMENT,
  customer_id INTEGER NOT NULL,
  invoice_number TEXT UNIQUE, -- human-readable: 'INV-2026-001'
  invoice_date TEXT NOT NULL,
  due_date TEXT,
  total_amount REAL NOT NULL,
  paid INTEGER DEFAULT 0, -- 1 = paid, 0 = unpaid
  paid_date TEXT,
  line_items TEXT, -- JSON array of job references: [{"job_id":1,"amount":45.00},...]
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

-- Trigger to update customers.updated_at
CREATE TRIGGER IF NOT EXISTS update_customer_timestamp 
AFTER UPDATE ON customers
BEGIN
  UPDATE customers SET updated_at = datetime('now') WHERE customer_id = NEW.customer_id;
END;
