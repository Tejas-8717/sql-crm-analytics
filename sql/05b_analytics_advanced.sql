USE crm_db;

WITH f AS (
    SELECT
      (SELECT COUNT(*) FROM leads) AS leads_total,
      (SELECT COUNT(*) FROM contacts WHERE lead_id IS NOT NULL) AS contacts_from_leads,
      (SELECT COUNT(*)
         FROM customers cu
         JOIN contacts c ON c.contact_id = cu.contact_id
        WHERE c.lead_id IS NOT NULL) AS customers_from_leads,
      (SELECT COUNT(DISTINCT cu.customer_id)
         FROM customers cu
         JOIN contacts c            ON c.contact_id  = cu.contact_id
         JOIN opportunities o       ON o.customer_id = cu.customer_id
         JOIN opportunity_stages s  ON s.stage_id    = o.stage_id
        WHERE c.lead_id IS NOT NULL AND s.is_won = TRUE) AS won_customers
)
SELECT 1 AS step, 'Leads' AS stage, leads_total AS n, 100.0 AS pct_of_leads FROM f
UNION ALL
SELECT 2, 'Contacts', contacts_from_leads,  ROUND(100 * contacts_from_leads  / leads_total, 1) FROM f
UNION ALL
SELECT 3, 'Customers', customers_from_leads, ROUND(100 * customers_from_leads / leads_total, 1) FROM f
UNION ALL
SELECT 4, 'Won a deal', won_customers,       ROUND(100 * won_customers       / leads_total, 1) FROM f
ORDER BY step;

WITH customer_revenue AS (
    SELECT cu.customer_id, c.full_name, SUM(o.amount) AS revenue
    FROM opportunities o
    JOIN opportunity_stages s ON s.stage_id    = o.stage_id
    JOIN customers cu         ON cu.customer_id = o.customer_id
    JOIN contacts c           ON c.contact_id   = cu.contact_id
    WHERE s.is_won = TRUE
    GROUP BY cu.customer_id, c.full_name
),
avg_rev AS (
    SELECT AVG(revenue) AS avg_revenue FROM customer_revenue
)
SELECT cr.full_name, cr.revenue, ROUND(a.avg_revenue, 2) AS avg_customer_revenue
FROM customer_revenue cr
CROSS JOIN avg_rev a
WHERE cr.revenue > a.avg_revenue
ORDER BY cr.revenue DESC
LIMIT 10;

WITH rep_rev AS (
    SELECT u.user_id, u.full_name, SUM(o.amount) AS revenue
    FROM opportunities o
    JOIN opportunity_stages s ON s.stage_id = o.stage_id
    JOIN users u              ON u.user_id  = o.owner_id
    WHERE s.is_won = TRUE
    GROUP BY u.user_id, u.full_name
)
SELECT full_name,
       revenue,
       RANK() OVER (ORDER BY revenue DESC)              AS rev_rank,
       ROUND(100 * revenue / SUM(revenue) OVER (), 1)   AS pct_of_total
FROM rep_rev
ORDER BY rev_rank;

WITH monthly AS (
    SELECT DATE_FORMAT(o.close_date, '%Y-%m') AS month,
           SUM(o.amount)                      AS revenue
    FROM opportunities o
    JOIN opportunity_stages s ON s.stage_id = o.stage_id
    WHERE s.is_won = TRUE
    GROUP BY DATE_FORMAT(o.close_date, '%Y-%m')
)
SELECT month,
       revenue,
       SUM(revenue) OVER (ORDER BY month)  AS running_total,
       LAG(revenue) OVER (ORDER BY month)  AS prev_month,
       ROUND(100 * (revenue - LAG(revenue) OVER (ORDER BY month))
                 / LAG(revenue) OVER (ORDER BY month), 1) AS mom_growth_pct
FROM monthly
ORDER BY month;

WITH ranked AS (
    SELECT o.opp_id, o.title, o.amount, u.full_name AS owner,
           ROW_NUMBER() OVER (PARTITION BY o.owner_id ORDER BY o.amount DESC) AS rn
    FROM opportunities o
    JOIN opportunity_stages s ON s.stage_id = o.stage_id
    JOIN users u              ON u.user_id  = o.owner_id
    WHERE s.is_won = TRUE
)
SELECT owner, rn AS deal_rank, title, amount
FROM ranked
WHERE rn <= 3
ORDER BY owner, rn;

SELECT cu.customer_id, c.full_name, cu.status
FROM customers cu
JOIN contacts c ON c.contact_id = cu.contact_id
WHERE cu.status = 'active'
  AND NOT EXISTS (
      SELECT 1
      FROM activities a
      WHERE a.customer_id = cu.customer_id
        AND a.activity_date >= NOW() - INTERVAL 90 DAY
  )
ORDER BY cu.customer_id
LIMIT 20;

SELECT o.opp_id, o.title, o.stage_id, o.amount
FROM opportunities o
WHERE o.amount > (
    SELECT AVG(o2.amount)
    FROM opportunities o2
    WHERE o2.stage_id = o.stage_id
)
ORDER BY o.amount DESC
LIMIT 15;
