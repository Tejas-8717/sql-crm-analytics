-- =====================================================
-- CRM Project - 01_schema.sql
-- MySQL 8.0.16+ (CHECK constraints are enforced)
-- Lifecycle: Lead -> Contact -> Customer -> Opportunity
-- =====================================================

DROP DATABASE IF EXISTS crm_db;
CREATE DATABASE crm_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE crm_db;

-- -----------------------------------------------------
-- 1. users: sales reps and admins
-- -----------------------------------------------------
CREATE TABLE users (
    user_id     INT AUTO_INCREMENT PRIMARY KEY,
    full_name   VARCHAR(100) NOT NULL,
    email       VARCHAR(150) NOT NULL UNIQUE,
    role        ENUM('admin','rep') NOT NULL DEFAULT 'rep',
    is_active   BOOLEAN NOT NULL DEFAULT TRUE,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 2. companies: organizations that contacts belong to
-- -----------------------------------------------------
CREATE TABLE companies (
    company_id  INT AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(150) NOT NULL,
    industry    VARCHAR(80),
    website     VARCHAR(200),
    city        VARCHAR(80),
    country     VARCHAR(80),
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_companies_name (name)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 3. leads: raw, unqualified prospects
-- -----------------------------------------------------
CREATE TABLE leads (
    lead_id       INT AUTO_INCREMENT PRIMARY KEY,
    full_name     VARCHAR(100) NOT NULL,
    email         VARCHAR(150) NOT NULL UNIQUE,
    phone         VARCHAR(30),
    company_name  VARCHAR(150),
    source        ENUM('website','referral','social_media','email_campaign','event','cold_call','other')
                  NOT NULL DEFAULT 'other',
    status        ENUM('new','contacted','qualified','converted','lost') NOT NULL DEFAULT 'new',
    owner_id      INT,
    created_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_leads_owner FOREIGN KEY (owner_id) REFERENCES users(user_id),
    INDEX idx_leads_status (status),
    INDEX idx_leads_source (source),
    INDEX idx_leads_owner (owner_id)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 4. contacts: a qualified lead becomes a contact
--    lead_id keeps the link back to the origin lead
-- -----------------------------------------------------
CREATE TABLE contacts (
    contact_id  INT AUTO_INCREMENT PRIMARY KEY,
    lead_id     INT UNIQUE,
    company_id  INT,
    full_name   VARCHAR(100) NOT NULL,
    email       VARCHAR(150) NOT NULL UNIQUE,
    phone       VARCHAR(30),
    job_title   VARCHAR(100),
    owner_id    INT,
    created_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_contacts_lead    FOREIGN KEY (lead_id)    REFERENCES leads(lead_id),
    CONSTRAINT fk_contacts_company FOREIGN KEY (company_id) REFERENCES companies(company_id),
    CONSTRAINT fk_contacts_owner   FOREIGN KEY (owner_id)   REFERENCES users(user_id),
    INDEX idx_contacts_company (company_id),
    INDEX idx_contacts_owner (owner_id)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 5. customers: a contact who has bought (or is buying)
-- -----------------------------------------------------
CREATE TABLE customers (
    customer_id        INT AUTO_INCREMENT PRIMARY KEY,
    contact_id         INT NOT NULL UNIQUE,
    company_id         INT,
    owner_id           INT,
    customer_since     DATE NOT NULL,
    status             ENUM('active','inactive','churned') NOT NULL DEFAULT 'active',
    created_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_customers_contact FOREIGN KEY (contact_id) REFERENCES contacts(contact_id),
    CONSTRAINT fk_customers_company FOREIGN KEY (company_id) REFERENCES companies(company_id),
    CONSTRAINT fk_customers_owner   FOREIGN KEY (owner_id)   REFERENCES users(user_id),
    INDEX idx_customers_status (status),
    INDEX idx_customers_owner (owner_id)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 6. opportunity_stages: lookup table for the pipeline
-- -----------------------------------------------------
CREATE TABLE opportunity_stages (
    stage_id         INT AUTO_INCREMENT PRIMARY KEY,
    stage_name       VARCHAR(50) NOT NULL UNIQUE,
    stage_order      TINYINT NOT NULL UNIQUE,
    win_probability  DECIMAL(5,2) NOT NULL CHECK (win_probability BETWEEN 0 AND 100),
    is_closed        BOOLEAN NOT NULL DEFAULT FALSE,
    is_won           BOOLEAN NOT NULL DEFAULT FALSE,
    CONSTRAINT chk_won_requires_closed CHECK (is_won = FALSE OR is_closed = TRUE)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 7. opportunities: sales deals tied to customers
-- -----------------------------------------------------
CREATE TABLE opportunities (
    opp_id       INT AUTO_INCREMENT PRIMARY KEY,
    customer_id  INT NOT NULL,
    stage_id     INT NOT NULL,
    owner_id     INT,
    title        VARCHAR(150) NOT NULL,
    amount       DECIMAL(12,2) NOT NULL CHECK (amount >= 0),
    close_date   DATE,
    created_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_opps_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_opps_stage    FOREIGN KEY (stage_id)    REFERENCES opportunity_stages(stage_id),
    CONSTRAINT fk_opps_owner    FOREIGN KEY (owner_id)    REFERENCES users(user_id),
    INDEX idx_opps_customer (customer_id),
    INDEX idx_opps_stage (stage_id),
    INDEX idx_opps_owner (owner_id),
    INDEX idx_opps_close_date (close_date)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 8. activities: calls, emails, meetings, notes
--    Each activity links to at least one record
-- -----------------------------------------------------
CREATE TABLE activities (
    activity_id    INT AUTO_INCREMENT PRIMARY KEY,
    activity_type  ENUM('call','email','meeting','note','task') NOT NULL,
    subject        VARCHAR(150) NOT NULL,
    notes          TEXT,
    activity_date  DATETIME NOT NULL,
    user_id        INT NOT NULL,
    lead_id        INT,
    contact_id     INT,
    customer_id    INT,
    opp_id         INT,
    created_at     TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_act_user     FOREIGN KEY (user_id)     REFERENCES users(user_id),
    CONSTRAINT fk_act_lead     FOREIGN KEY (lead_id)     REFERENCES leads(lead_id),
    CONSTRAINT fk_act_contact  FOREIGN KEY (contact_id)  REFERENCES contacts(contact_id),
    CONSTRAINT fk_act_customer FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_act_opp      FOREIGN KEY (opp_id)      REFERENCES opportunities(opp_id),
    CONSTRAINT chk_act_has_target CHECK (
        lead_id IS NOT NULL OR contact_id IS NOT NULL
        OR customer_id IS NOT NULL OR opp_id IS NOT NULL
    ),
    INDEX idx_act_date (activity_date),
    INDEX idx_act_user (user_id),
    INDEX idx_act_lead (lead_id),
    INDEX idx_act_contact (contact_id),
    INDEX idx_act_customer (customer_id),
    INDEX idx_act_opp (opp_id)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- 9. audit_log: filled by triggers (see 04_procedures_triggers.sql)
-- -----------------------------------------------------
CREATE TABLE audit_log (
    log_id      BIGINT AUTO_INCREMENT PRIMARY KEY,
    table_name  VARCHAR(50) NOT NULL,
    record_id   INT NOT NULL,
    action      ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    old_values  JSON,
    new_values  JSON,
    changed_at  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_audit_table_record (table_name, record_id),
    INDEX idx_audit_changed_at (changed_at)
) ENGINE=InnoDB;

-- -----------------------------------------------------
-- Reference data: pipeline stages
-- -----------------------------------------------------
INSERT INTO opportunity_stages (stage_name, stage_order, win_probability, is_closed, is_won) VALUES
    ('New',        1,  10.00, FALSE, FALSE),
    ('Qualified',  2,  30.00, FALSE, FALSE),
    ('Proposal',   3,  60.00, FALSE, FALSE),
    ('Won',        4, 100.00, TRUE,  TRUE),
    ('Lost',       5,   0.00, TRUE,  FALSE);
    
    SHOW TABLES;
    
    SELECT * FROM opportunity_stages;