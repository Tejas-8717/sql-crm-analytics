-- =====================================================
-- CRM Project - 05_analytics.sql
-- Part A: Joins     Part B: Aggregations
-- Run ONE query at a time: click inside it, then use the
-- second lightning bolt (executes the current statement).
-- =====================================================
USE crm_db;

-- =====================================================
-- PART A: JOINS
-- =====================================================

-- A1. Top 20 opportunities with customer, company, stage and owner
--     (INNER JOIN for required links, LEFT JOIN for optional ones)
SELECT o.opp_id,
       o.title,
       c.full_name      AS customer_name,
       co.name          AS company,
       s.stage_name,
       o.amount,
       u.full_name      AS owner
FROM opportunities o
JOIN customers cu          ON cu.customer_id = o.customer_id
JOIN contacts c            ON c.contact_id   = cu.contact_id
LEFT JOIN companies co     ON co.company_id  = cu.company_id
JOIN opportunity_stages s  ON s.stage_id     = o.stage_id
LEFT JOIN users u          ON u.user_id      = o.owner_id
ORDER BY o.amount DESC
LIMIT 20;

-- A2. Trace the full lifecycle: Lead -> Contact -> Customer
--     (customers.contact_id may not exist yet, so LEFT JOIN)
SELECT l.lead_id,
       l.full_name,
       l.status          AS lead_status,
       c.contact_id,
       cu.customer_id
FROM leads l
JOIN contacts c            ON c.lead_id    = l.lead_id
LEFT JOIN customers cu     ON cu.contact_id = c.contact_id
ORDER BY l.lead_id
LIMIT 20;

-- A3. Leads that have NO activity logged (anti-join pattern:
--     LEFT JOIN + IS NULL finds rows with no match)
SELECT l.lead_id, l.full_name, l.status, l.created_at
FROM leads l
LEFT JOIN activities a ON a.lead_id = l.lead_id
WHERE a.activity_id IS NULL
ORDER BY l.created_at
LIMIT 20;

-- =====================================================
-- PART B: AGGREGATIONS
-- =====================================================

-- B1. Lead conversion rate by source
--     SUM(condition) counts rows where the condition is true
SELECT source,
       COUNT(*)                                          AS total_leads,
       SUM(status = 'converted')                         AS converted,
       ROUND(100 * SUM(status = 'converted') / COUNT(*), 1) AS conversion_pct
FROM leads
GROUP BY source
ORDER BY conversion_pct DESC;

-- B2. Won revenue by month
SELECT DATE_FORMAT(o.close_date, '%Y-%m') AS month,
       COUNT(*)                           AS deals_won,
       SUM(o.amount)                      AS revenue
FROM opportunities o
JOIN opportunity_stages s ON s.stage_id = o.stage_id
WHERE s.is_won = TRUE
GROUP BY DATE_FORMAT(o.close_date, '%Y-%m')
ORDER BY month;

-- B3. Sales rep performance (HAVING filters AFTER grouping)
SELECT u.full_name,
       COUNT(*)                AS deals_won,
       SUM(o.amount)           AS revenue,
       ROUND(AVG(o.amount), 2) AS avg_deal_size
FROM opportunities o
JOIN opportunity_stages s ON s.stage_id = o.stage_id
JOIN users u              ON u.user_id   = o.owner_id
WHERE s.is_won = TRUE
GROUP BY u.user_id, u.full_name
HAVING COUNT(*) >= 5
ORDER BY revenue DESC;

-- B4. Pipeline by stage, with probability-weighted value
--     (LEFT JOIN from stages so empty stages still appear)
SELECT s.stage_name,
       COUNT(o.opp_id)                                        AS opps,
       COALESCE(SUM(o.amount), 0)                             AS total_amount,
       ROUND(COALESCE(SUM(o.amount * s.win_probability / 100), 0), 2) AS weighted_amount
FROM opportunity_stages s
LEFT JOIN opportunities o ON o.stage_id = s.stage_id
GROUP BY s.stage_id, s.stage_name, s.stage_order
ORDER BY s.stage_order;

-- =====================================================
-- YOUR PRACTICE TASKS (write these yourself)
-- =====================================================
-- T1. List customers (name + company) who have NO opportunities.
-- T2. Count leads per owner (rep name) and per status.
-- T3. Which lead source produced the most WON revenue?
--     Hint: leads -> contacts -> customers -> opportunities