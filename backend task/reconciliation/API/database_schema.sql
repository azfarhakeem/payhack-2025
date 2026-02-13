-- ============================================================================
-- Tideline — Payment Reconciliation Platform
-- PostgreSQL Database Schema
-- ============================================================================
--
-- Entity Relationship Diagram (ERD)
--
--  users ──────────────< uploads
--    │                     │
--    │                     ├── field_mappings
--    │                     │
--    │                     └──< transactions
--    │
--    ├──< audit_events
--    │
--    ├──< notification_preferences
--    │
--    └──< notifications
--
--  reconciliation_runs ──< reconciliation_records ──< transaction_legs
--         │                       │
--         │                       └──< discrepancies
--         │
--         └── references 3 uploads (psp, cashier, erp)
--
--  matching_config (singleton / global settings)
--
-- ============================================================================

-- --------------------------------------------------------------------------
-- ENUMs
-- --------------------------------------------------------------------------

CREATE TYPE actor_type AS ENUM ('system', 'user', 'ai');

CREATE TYPE record_status AS ENUM ('matched', 'partial', 'unmatched', 'discrepancy');

CREATE TYPE match_type AS ENUM ('exact', 'unmatched', 'discrepancy');

CREATE TYPE discrepancy_sub_type AS ENUM (
  'missing',
  'timing',
  'amount-mismatch',
  'duplicate',
  'fx-rate',
  'fee'
);

CREATE TYPE discrepancy_severity AS ENUM ('low', 'medium', 'high', 'critical');

CREATE TYPE leg_status AS ENUM ('Processed', 'Recorded', 'Verified', 'Missing');

CREATE TYPE audit_category AS ENUM (
  'reconciliation',
  'resolution',
  'config',
  'review',
  'export'
);

CREATE TYPE notification_type AS ENUM ('info', 'warning', 'error', 'success');

CREATE TYPE stakeholder_system AS ENUM ('psp', 'cashier', 'erp');

-- --------------------------------------------------------------------------
-- 1. users
-- --------------------------------------------------------------------------
-- Actors from the audit trail: human analysts, system accounts, AI agents.

CREATE TABLE users (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name          TEXT        NOT NULL,           -- e.g. "Sarah Chen", "AI Agent v2.4.1"
  email         TEXT        UNIQUE,             -- NULL for system/AI actors
  actor_type    actor_type  NOT NULL DEFAULT 'user',
  role          TEXT,                            -- e.g. "analyst", "admin", "system"
  is_active     BOOLEAN     NOT NULL DEFAULT TRUE,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE users IS 'All actors: human users, system accounts, and AI agents';

-- --------------------------------------------------------------------------
-- 2. uploads
-- --------------------------------------------------------------------------
-- File upload records per stakeholder. One upload = one CSV from PSP, Cashier, or ERP.

CREATE TABLE uploads (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID        NOT NULL REFERENCES users(id),
  system          stakeholder_system NOT NULL,    -- 'psp', 'cashier', 'erp'
  filename        TEXT        NOT NULL,
  file_size_bytes BIGINT,
  row_count       INTEGER,
  status          TEXT        NOT NULL DEFAULT 'pending',  -- pending, validating, validated, error
  error_message   TEXT,
  uploaded_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  validated_at    TIMESTAMPTZ
);

CREATE INDEX idx_uploads_user_id ON uploads(user_id);
CREATE INDEX idx_uploads_system ON uploads(system);

COMMENT ON TABLE uploads IS 'File upload records per stakeholder system (PSP, Cashier, ERP)';

-- --------------------------------------------------------------------------
-- 3. field_mappings
-- --------------------------------------------------------------------------
-- Column-to-field mappings per upload. Maps source CSV columns to the 16
-- standardized transaction fields.

CREATE TABLE field_mappings (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  upload_id       UUID        NOT NULL REFERENCES uploads(id) ON DELETE CASCADE,
  source_column   TEXT        NOT NULL,          -- e.g. "gross_amount", "posted_amount"
  target_field    TEXT        NOT NULL,          -- e.g. "grossAmount", "reference"
  transform       TEXT,                          -- optional transform rule
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_field_mappings_upload_id ON field_mappings(upload_id);

COMMENT ON TABLE field_mappings IS 'Maps source CSV columns to standardized transaction fields per upload';

-- --------------------------------------------------------------------------
-- 4. transactions
-- --------------------------------------------------------------------------
-- Normalized transaction records. Each row = one transaction from one system.
-- The 16 standardized fields plus metadata.
--
-- NOTE: For ERP transactions, `gross_amount` actually stores the NET amount
-- (posted_amount). See API README "Amount Comparison Rules" for details.

CREATE TABLE transactions (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  upload_id         UUID        NOT NULL REFERENCES uploads(id) ON DELETE CASCADE,
  system            stakeholder_system NOT NULL,
  system_id         TEXT        NOT NULL,         -- original ID: psp_txn_id / internal_id / erp_doc_number
  reference         TEXT        NOT NULL,         -- PRIMARY MATCH KEY across all 3 systems
  gross_amount      NUMERIC(18,2) NOT NULL,       -- PSP/Cashier=GROSS, ERP=NET (posted_amount)
  net_amount        NUMERIC(18,2),
  fee               NUMERIC(18,2) DEFAULT 0,
  currency          TEXT        NOT NULL DEFAULT 'USD',
  transaction_date  DATE        NOT NULL,
  settlement_date   DATE,
  client_id         TEXT,
  client_name       TEXT,
  description       TEXT,
  status            TEXT,                          -- processing status from source
  payment_method    TEXT,
  settlement_bank   TEXT,
  bank_country      TEXT,
  fx_rate           NUMERIC(12,6),
  is_duplicate      BOOLEAN     NOT NULL DEFAULT FALSE,
  raw_data          JSONB,                         -- original row from CSV for audit
  created_at        TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_transactions_reference ON transactions(reference);
CREATE INDEX idx_transactions_upload_id ON transactions(upload_id);
CREATE INDEX idx_transactions_system ON transactions(system);
CREATE INDEX idx_transactions_client_id ON transactions(client_id);
CREATE INDEX idx_transactions_transaction_date ON transactions(transaction_date);

COMMENT ON TABLE transactions IS 'Normalized transaction records from all 3 systems. ERP gross_amount = NET.';
COMMENT ON COLUMN transactions.gross_amount IS 'For ERP: this is actually NET (posted_amount). See amount comparison rules.';

-- --------------------------------------------------------------------------
-- 5. reconciliation_runs
-- --------------------------------------------------------------------------
-- Each reconciliation run references 3 uploads and stores summary statistics.

CREATE TABLE reconciliation_runs (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  psp_upload_id     UUID        NOT NULL REFERENCES uploads(id),
  cashier_upload_id UUID        NOT NULL REFERENCES uploads(id),
  erp_upload_id     UUID        NOT NULL REFERENCES uploads(id),
  run_by            UUID        REFERENCES users(id),
  status            TEXT        NOT NULL DEFAULT 'running',  -- running, completed, failed
  -- Summary stats matching frontend: total/matched/partial/unmatched/discrepancies/matchRate
  total_transactions  INTEGER,
  matched_count       INTEGER,
  partial_count       INTEGER,
  unmatched_count     INTEGER,
  discrepancy_count   INTEGER,
  match_rate          NUMERIC(5,1),                -- e.g. 95.4
  duration_ms         INTEGER,                     -- how long the run took
  run_at              TIMESTAMPTZ NOT NULL DEFAULT now(),
  completed_at        TIMESTAMPTZ
);

CREATE INDEX idx_recon_runs_run_at ON reconciliation_runs(run_at DESC);

COMMENT ON TABLE reconciliation_runs IS 'Each reconciliation run referencing 3 uploads with summary stats';

-- --------------------------------------------------------------------------
-- 6. reconciliation_records
-- --------------------------------------------------------------------------
-- Per-transaction match result. Matches the frontend ReconciliationRecord interface.
--
-- Fields: id, transactionRef, pspAmount, cashierAmount, erpAmount,
--         matchScore, status, matchType, discrepancySubType, timestamp

CREATE TABLE reconciliation_records (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reconciliation_run_id UUID           NOT NULL REFERENCES reconciliation_runs(id) ON DELETE CASCADE,
  transaction_ref       TEXT           NOT NULL,
  psp_amount            TEXT           NOT NULL,     -- display string e.g. "$12,450.00" or "-"
  cashier_amount        TEXT           NOT NULL,
  erp_amount            TEXT           NOT NULL,
  match_score           INTEGER        NOT NULL CHECK (match_score >= 0 AND match_score <= 100),
  status                record_status  NOT NULL,
  match_type            match_type     NOT NULL,
  discrepancy_sub_type  discrepancy_sub_type,        -- NULL if fully matched
  variance              TEXT,                         -- e.g. "$0.50", "N/A"
  overall_status        TEXT,                         -- "Reconciled", "Partial", "Unmatched", "Discrepancy"
  timestamp             TIMESTAMPTZ    NOT NULL,
  created_at            TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX idx_recon_records_run_id ON reconciliation_records(reconciliation_run_id);
CREATE INDEX idx_recon_records_status ON reconciliation_records(status);
CREATE INDEX idx_recon_records_transaction_ref ON reconciliation_records(transaction_ref);

COMMENT ON TABLE reconciliation_records IS 'Per-transaction match result. Matches frontend ReconciliationRecord interface exactly.';

-- --------------------------------------------------------------------------
-- 7. transaction_legs
-- --------------------------------------------------------------------------
-- Each reconciliation record has 3 legs: PSP, Cashier, ERP.
-- Each leg stores the per-system amount, status, timestamp, and description.
-- 15 records × 3 legs = 45 rows in the sample data.

CREATE TABLE transaction_legs (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reconciliation_record_id UUID           NOT NULL REFERENCES reconciliation_records(id) ON DELETE CASCADE,
  system                  stakeholder_system NOT NULL,  -- 'psp', 'cashier', 'erp'
  amount                  TEXT           NOT NULL,      -- display string e.g. "$12,450.00" or "-"
  description             TEXT,                          -- e.g. "Visa credit card deposit via payment gateway"
  status                  leg_status     NOT NULL,      -- Processed, Recorded, Verified, Missing
  timestamp               TEXT           NOT NULL,      -- e.g. "2024-01-15 09:30:02" or "-"
  created_at              TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX idx_transaction_legs_record_id ON transaction_legs(reconciliation_record_id);

COMMENT ON TABLE transaction_legs IS 'Per-system leg for each reconciliation record. 3 rows per record (PSP, Cashier, ERP).';

-- --------------------------------------------------------------------------
-- 8. discrepancies
-- --------------------------------------------------------------------------
-- Detailed discrepancy records with type, severity, and per-system values.

CREATE TABLE discrepancies (
  id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  reconciliation_record_id UUID           NOT NULL REFERENCES reconciliation_records(id) ON DELETE CASCADE,
  reconciliation_run_id   UUID           NOT NULL REFERENCES reconciliation_runs(id),
  transaction_ref         TEXT           NOT NULL,
  type                    discrepancy_sub_type NOT NULL,
  severity                discrepancy_severity NOT NULL,
  description             TEXT           NOT NULL,
  variance                TEXT,                          -- e.g. "$0.50", "N/A"
  psp_value               JSONB,                         -- { "amount": "$8,320.50", ... }
  cashier_value           JSONB,                         -- { "amount": "$8,320.00", ... }
  erp_value               JSONB,                         -- { "amount": "$8,320.50", ... }
  suggested_resolution    TEXT,
  resolved                BOOLEAN        NOT NULL DEFAULT FALSE,
  resolved_by             UUID           REFERENCES users(id),
  resolved_at             TIMESTAMPTZ,
  resolution_notes        TEXT,
  created_at              TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX idx_discrepancies_run_id ON discrepancies(reconciliation_run_id);
CREATE INDEX idx_discrepancies_record_id ON discrepancies(reconciliation_record_id);
CREATE INDEX idx_discrepancies_type ON discrepancies(type);
CREATE INDEX idx_discrepancies_severity ON discrepancies(severity);

COMMENT ON TABLE discrepancies IS 'Detailed discrepancy records with per-system JSONB values for flexible comparison';

-- --------------------------------------------------------------------------
-- 9. audit_events
-- --------------------------------------------------------------------------
-- Full audit trail for all actions: system, user, and AI events.

CREATE TABLE audit_events (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_id    UUID           REFERENCES users(id),
  actor_name  TEXT           NOT NULL,           -- denormalized for display: "Sarah Chen", "AI Agent v2.4.1"
  actor_type  actor_type     NOT NULL,
  action      TEXT           NOT NULL,           -- e.g. "Batch Started", "Viewed Details", "Auto-Resolved"
  target      TEXT           NOT NULL,           -- e.g. "BATCH-2024-0115", "TXN-2024-003"
  details     TEXT,
  category    audit_category NOT NULL,
  metadata    JSONB,                              -- extra structured data if needed
  created_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX idx_audit_events_actor_type ON audit_events(actor_type);
CREATE INDEX idx_audit_events_category ON audit_events(category);
CREATE INDEX idx_audit_events_target ON audit_events(target);
CREATE INDEX idx_audit_events_created_at ON audit_events(created_at DESC);

COMMENT ON TABLE audit_events IS 'Complete audit trail for system, user, and AI actions';

-- --------------------------------------------------------------------------
-- 10. notifications
-- --------------------------------------------------------------------------
-- User-facing notifications triggered by system events.

CREATE TABLE notifications (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     UUID              NOT NULL REFERENCES users(id),
  type        notification_type NOT NULL DEFAULT 'info',
  title       TEXT              NOT NULL,
  message     TEXT              NOT NULL,
  link        TEXT,                              -- optional deep link to relevant page
  is_read     BOOLEAN           NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ       NOT NULL DEFAULT now(),
  read_at     TIMESTAMPTZ
);

CREATE INDEX idx_notifications_user_id ON notifications(user_id);
CREATE INDEX idx_notifications_unread ON notifications(user_id, is_read) WHERE NOT is_read;

COMMENT ON TABLE notifications IS 'User-facing notifications with read/unread tracking';

-- --------------------------------------------------------------------------
-- 11. matching_config
-- --------------------------------------------------------------------------
-- Global settings for the reconciliation engine.

CREATE TABLE matching_config (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  fuzzy_threshold       NUMERIC(5,2) NOT NULL DEFAULT 0.85,    -- minimum similarity score for fuzzy match
  amount_tolerance      NUMERIC(18,2) NOT NULL DEFAULT 0.01,   -- amount difference tolerance (cents)
  date_tolerance_days   INTEGER       NOT NULL DEFAULT 5,       -- max days gap for timing check
  auto_resolve_confidence NUMERIC(5,2) NOT NULL DEFAULT 0.92,  -- min AI confidence for auto-resolve
  duplicate_check       BOOLEAN       NOT NULL DEFAULT TRUE,
  fx_rate_tolerance_pct NUMERIC(5,2) NOT NULL DEFAULT 1.00,    -- max FX rate difference percentage
  updated_by            UUID          REFERENCES users(id),
  updated_at            TIMESTAMPTZ   NOT NULL DEFAULT now()
);

COMMENT ON TABLE matching_config IS 'Global reconciliation engine settings (singleton table)';

-- Insert default config
INSERT INTO matching_config (
  fuzzy_threshold, amount_tolerance, date_tolerance_days,
  auto_resolve_confidence, duplicate_check, fx_rate_tolerance_pct
) VALUES (0.85, 0.01, 5, 0.92, TRUE, 1.00);

-- --------------------------------------------------------------------------
-- 12. notification_preferences
-- --------------------------------------------------------------------------
-- Per-user notification channel and digest settings.

CREATE TABLE notification_preferences (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID    NOT NULL REFERENCES users(id) UNIQUE,
  email_enabled   BOOLEAN NOT NULL DEFAULT TRUE,
  in_app_enabled  BOOLEAN NOT NULL DEFAULT TRUE,
  slack_enabled   BOOLEAN NOT NULL DEFAULT FALSE,
  slack_channel   TEXT,
  digest_enabled  BOOLEAN NOT NULL DEFAULT FALSE,
  digest_frequency TEXT   DEFAULT 'daily',         -- 'daily', 'weekly', 'realtime'
  notify_on_discrepancy  BOOLEAN NOT NULL DEFAULT TRUE,
  notify_on_completion   BOOLEAN NOT NULL DEFAULT TRUE,
  notify_on_ai_resolution BOOLEAN NOT NULL DEFAULT TRUE,
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE notification_preferences IS 'Per-user notification channel and digest settings';

-- ============================================================================
-- Seed Data: Sample Users (actors from audit trail)
-- ============================================================================

INSERT INTO users (name, email, actor_type, role) VALUES
  ('Sarah Chen',             'sarah.chen@company.com',  'user',   'analyst'),
  ('James Lee',              'james.lee@company.com',   'user',   'analyst'),
  ('Reconciliation Engine',  NULL,                      'system', 'system'),
  ('System Scheduler',       NULL,                      'system', 'system'),
  ('Admin Config',           NULL,                      'system', 'admin'),
  ('AI Agent v2.4.1',        NULL,                      'ai',     'ai-agent');
