-- CRM Project - 03_views.sql
-- Views save your best queries under a name so the
-- Safe to re-run (CREATE OR REPLACE).

USE crm_db;

-- Every opportunity with customer, company, stage and owner details
CREATE OR REPLACE VIEW v_sales_pipeline AS
SELECT o.opp_id,
       o.title,
       c.full_name       AS customer_name,
       co.name           AS company,
       s.stage_name,
       s.stage_order,
       s.is_closed,
       s.is_won,
       o.amount,
       ROUND(o.amount * s.win_probability / 100, 2) AS weighted_amount,
       o.close_date,
       u.full_name       AS owner
FROM opportunities o
JOIN customers cu          ON cu.customer_id = o.customer_id
JOIN contacts c            ON c.contact_id   = cu.contact_id
LEFT JOIN companies co     ON co.company_id  = cu.company_id
JOIN opportunity_stages s  ON s.stage_id     = o.stage_id
LEFT JOIN users u          ON u.user_id      = o.owner_id;

-- One row per rep with headline numbers
-- (separate subqueries avoid double counting from multiple joins)
CREATE OR REPLACE VIEW v_rep_performance AS
SELECT u.user_id,
       u.full_name,
       (SELECT COUNT(*) FROM leads l
         WHERE l.owner_id = u.user_id) AS leads_owned,
       (SELECT COUNT(*) FROM opportunities o
          JOIN opportunity_stages s ON s.stage_id = o.stage_id
         WHERE o.owner_id = u.user_id AND s.is_won = TRUE) AS deals_won,
       (SELECT COALESCE(SUM(o.amount), 0) FROM opportunities o
          JOIN opportunity_stages s ON s.stage_id = o.stage_id
         WHERE o.owner_id = u.user_id AND s.is_won = TRUE) AS revenue_won,
       (SELECT COALESCE(SUM(o.amount), 0) FROM opportunities o
          JOIN opportunity_stages s ON s.stage_id = o.stage_id
         WHERE o.owner_id = u.user_id AND s.is_closed = FALSE) AS open_pipeline
FROM users u
WHERE u.role = 'rep';

-- Won revenue per month (feeds the revenue trend chart)
CREATE OR REPLACE VIEW v_monthly_revenue AS
SELECT DATE_FORMAT(o.close_date, '%Y-%m') AS month,
       COUNT(*)                           AS deals_won,
       SUM(o.amount)                      AS revenue
FROM opportunities o
JOIN opportunity_stages s ON s.stage_id = o.stage_id
WHERE s.is_won = TRUE
GROUP BY DATE_FORMAT(o.close_date, '%Y-%m');
