-- =====================================================
-- CRM Project - 06_performance.sql
-- Index tuning with EXPLAIN. Run ONE statement at a time.
-- Screenshot the BEFORE and AFTER results for your README.
-- =====================================================
USE crm_db;

-- ---------- Experiment 1: searching an unindexed column ----------

-- BEFORE: look at the "type" and "rows" columns.
-- type = ALL means a full table scan (reads every row).
EXPLAIN SELECT * FROM leads WHERE full_name = 'John Smith';

-- Add an index
CREATE INDEX idx_leads_full_name ON leads (full_name);

-- AFTER: type should now be "ref" and rows should be tiny.
EXPLAIN SELECT * FROM leads WHERE full_name = 'John Smith';

-- EXPLAIN ANALYZE actually runs the query and shows real timings (MySQL 8.0.18+)
EXPLAIN ANALYZE SELECT * FROM leads WHERE full_name = 'John Smith';

-- ---------- Experiment 2: where an index does NOT help ----------

-- Leading wildcard: the index on full_name can't be used (full scan again)
EXPLAIN SELECT * FROM leads WHERE full_name LIKE '%Smith';

-- Trailing wildcard: the index CAN be used (range scan)
EXPLAIN SELECT * FROM leads WHERE full_name LIKE 'John%';

-- Wrapping the column in a function also blocks the index
EXPLAIN SELECT * FROM leads WHERE UPPER(full_name) = 'JOHN SMITH';

-- ---------- Experiment 3: composite index ----------

-- A common dashboard filter: leads of one rep with one status
EXPLAIN SELECT * FROM leads WHERE owner_id = 3 AND status = 'qualified';

CREATE INDEX idx_leads_owner_status ON leads (owner_id, status);

EXPLAIN SELECT * FROM leads WHERE owner_id = 3 AND status = 'qualified';

-- ---------- See all indexes on a table ----------
SHOW INDEX FROM leads;

-- ---------- Cleanup (optional): remove experiment indexes ----------
-- DROP INDEX idx_leads_full_name   ON leads;
-- DROP INDEX idx_leads_owner_status ON leads;