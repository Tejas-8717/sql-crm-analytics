-- CRM Project - 04_procedures_triggers.sql
-- Stored procedure + transaction, and audit triggers.
-- Safe to re-run.
USE crm_db;

DROP PROCEDURE IF EXISTS convert_lead_to_customer;
DROP TRIGGER   IF EXISTS trg_leads_after_update;
DROP TRIGGER   IF EXISTS trg_customers_after_update;
DROP TRIGGER   IF EXISTS trg_opps_after_update;
DROP TRIGGER   IF EXISTS trg_opps_after_delete;

DELIMITER //

-- convert_lead_to_customer
-- Turns a lead into a contact AND a customer, marks the
-- lead as converted, and logs a note. ALL-OR-NOTHING:
-- if any step fails, everything is rolled back.
CREATE PROCEDURE convert_lead_to_customer(
    IN  p_lead_id     INT,
    IN  p_company_id  INT,            -- may be NULL
    IN  p_job_title   VARCHAR(100),   -- may be NULL
    OUT p_customer_id INT
)
BEGIN
    DECLARE v_name    VARCHAR(100);
    DECLARE v_email   VARCHAR(150);
    DECLARE v_phone   VARCHAR(30);
    DECLARE v_owner   INT;
    DECLARE v_status  VARCHAR(20);
    DECLARE v_contact INT;

    -- On ANY SQL error: undo everything, then re-raise the error
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    -- Lock the lead row so two people can't convert it at the same time
    SELECT full_name, email, phone, owner_id, status
      INTO v_name, v_email, v_phone, v_owner, v_status
      FROM leads
     WHERE lead_id = p_lead_id
       FOR UPDATE;

    IF v_status IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lead not found';
    END IF;
    IF v_status = 'converted' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lead is already converted';
    END IF;
    IF v_status = 'lost' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Lost leads cannot be converted';
    END IF;

    -- 1) Lead -> Contact
    INSERT INTO contacts (lead_id, company_id, full_name, email, phone, job_title, owner_id)
    VALUES (p_lead_id, p_company_id, v_name, v_email, v_phone, p_job_title, v_owner);
    SET v_contact = LAST_INSERT_ID();

    -- 2) Contact -> Customer
    INSERT INTO customers (contact_id, company_id, owner_id, customer_since)
    VALUES (v_contact, p_company_id, v_owner, CURDATE());
    SET p_customer_id = LAST_INSERT_ID();

    -- 3) Mark the lead as converted
    UPDATE leads SET status = 'converted' WHERE lead_id = p_lead_id;

    -- 4) Log it (activities.user_id is NOT NULL, so fall back to admin id 1)
    INSERT INTO activities (activity_type, subject, notes, activity_date, user_id, customer_id)
    VALUES ('note', 'Lead converted to customer',
            CONCAT('Converted from lead #', p_lead_id), NOW(),
            COALESCE(v_owner, 1), p_customer_id);

    COMMIT;
END //

-- AUDIT TRIGGERS: write old/new values into audit_log
-- (only when a tracked column actually changed;
--  <=> is MySQL's NULL-safe equals)
CREATE TRIGGER trg_leads_after_update
AFTER UPDATE ON leads
FOR EACH ROW
BEGIN
    IF NOT (OLD.status   <=> NEW.status
        AND OLD.owner_id <=> NEW.owner_id
        AND OLD.email    <=> NEW.email) THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values)
        VALUES ('leads', OLD.lead_id, 'UPDATE',
                JSON_OBJECT('status', OLD.status, 'owner_id', OLD.owner_id, 'email', OLD.email),
                JSON_OBJECT('status', NEW.status, 'owner_id', NEW.owner_id, 'email', NEW.email));
    END IF;
END //

CREATE TRIGGER trg_customers_after_update
AFTER UPDATE ON customers
FOR EACH ROW
BEGIN
    IF NOT (OLD.status   <=> NEW.status
        AND OLD.owner_id <=> NEW.owner_id) THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values)
        VALUES ('customers', OLD.customer_id, 'UPDATE',
                JSON_OBJECT('status', OLD.status, 'owner_id', OLD.owner_id),
                JSON_OBJECT('status', NEW.status, 'owner_id', NEW.owner_id));
    END IF;
END //

CREATE TRIGGER trg_opps_after_update
AFTER UPDATE ON opportunities
FOR EACH ROW
BEGIN
    IF NOT (OLD.stage_id   <=> NEW.stage_id
        AND OLD.amount     <=> NEW.amount
        AND OLD.close_date <=> NEW.close_date
        AND OLD.owner_id   <=> NEW.owner_id) THEN
        INSERT INTO audit_log (table_name, record_id, action, old_values, new_values)
        VALUES ('opportunities', OLD.opp_id, 'UPDATE',
                JSON_OBJECT('stage_id', OLD.stage_id, 'amount', OLD.amount,
                            'close_date', OLD.close_date, 'owner_id', OLD.owner_id),
                JSON_OBJECT('stage_id', NEW.stage_id, 'amount', NEW.amount,
                            'close_date', NEW.close_date, 'owner_id', NEW.owner_id));
    END IF;
END //

CREATE TRIGGER trg_opps_after_delete
AFTER DELETE ON opportunities
FOR EACH ROW
BEGIN
    INSERT INTO audit_log (table_name, record_id, action, old_values, new_values)
    VALUES ('opportunities', OLD.opp_id, 'DELETE',
            JSON_OBJECT('stage_id', OLD.stage_id, 'amount', OLD.amount,
                        'title', OLD.title, 'customer_id', OLD.customer_id),
            NULL);
END //

DELIMITER ;

-- =====================================================
-- TESTS (run these ONE AT A TIME after the file above)
-- =====================================================

-- Test 1: successful conversion
--   (a) pick a lead that is not converted yet
-- SELECT lead_id, full_name, status FROM leads WHERE status IN ('new','contacted','qualified') LIMIT 1;
--   (b) convert it (replace 5 with your lead_id; company 1 exists)
-- CALL convert_lead_to_customer(5, 1, 'Manager', @new_customer_id);
-- SELECT @new_customer_id;
--   (c) check all 4 effects
-- SELECT * FROM leads     WHERE lead_id = 5;
-- SELECT * FROM contacts  WHERE lead_id = 5;
-- SELECT * FROM customers WHERE customer_id = @new_customer_id;
-- SELECT * FROM audit_log ORDER BY log_id DESC LIMIT 5;

-- Test 2: converting the SAME lead again must FAIL
-- CALL convert_lead_to_customer(5, 1, 'Manager', @x);   -- "Lead is already converted"

-- Test 3: ROLLBACK proof. Company 99999 does not exist -> the foreign key fails
--         halfway through, and nothing should be left behind.
--   (replace 7 with another unconverted lead_id)
-- CALL convert_lead_to_customer(7, 99999, 'Manager', @x);   -- FK error
-- SELECT status FROM leads WHERE lead_id = 7;               -- still NOT 'converted'
-- SELECT * FROM contacts WHERE lead_id = 7;                 -- no rows

-- Test 4: trigger
-- UPDATE opportunities SET amount = amount + 100 WHERE opp_id = 1;
-- SELECT * FROM audit_log WHERE table_name = 'opportunities' ORDER BY log_id DESC LIMIT 3;