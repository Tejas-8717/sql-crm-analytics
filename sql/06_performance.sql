USE crm_db;
EXPLAIN SELECT * FROM leads WHERE full_name = 'John Smith';

-- Add an index
CREATE INDEX idx_leads_full_name ON leads (full_name);

-- AFTER: type should now be "ref" and rows should be tiny.
EXPLAIN SELECT * FROM leads WHERE full_name = 'John Smith';

-- EXPLAIN ANALYZE actually runs the query and shows real timings (MySQL 8.0.18+)
EXPLAIN ANALYZE SELECT * FROM leads WHERE full_name = 'John Smith';


-- Leading wildcard: the index on full_name can't be used (full scan again)
EXPLAIN SELECT * FROM leads WHERE full_name LIKE '%Smith';

-- Trailing wildcard: the index CAN be used (range scan)
EXPLAIN SELECT * FROM leads WHERE full_name LIKE 'John%';

-- Wrapping the column in a function also blocks the index
EXPLAIN SELECT * FROM leads WHERE UPPER(full_name) = 'JOHN SMITH';


-- A common dashboard filter: leads of one rep with one status
EXPLAIN SELECT * FROM leads WHERE owner_id = 3 AND status = 'qualified';

CREATE INDEX idx_leads_owner_status ON leads (owner_id, status);

EXPLAIN SELECT * FROM leads WHERE owner_id = 3 AND status = 'qualified';
SHOW INDEX FROM leads;
