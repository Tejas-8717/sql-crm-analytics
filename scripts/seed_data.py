"""
Seed the CRM database with realistic fake data.
Run AFTER sql/01_schema.sql has been executed.

Usage:  python scripts/seed_data.py
"""
import os
import re
import random
from datetime import datetime, timedelta

import mysql.connector
from dotenv import load_dotenv
from faker import Faker

load_dotenv()
fake = Faker()
Faker.seed(42)
random.seed(42)

# ---------- Settings ----------
N_USERS = 8
N_COMPANIES = 150
N_LEADS = 1000
N_DIRECT_CONTACTS = 60      # contacts that never came from a lead
N_ACTIVITIES = 3000
NOW = datetime.now().replace(microsecond=0)
START = NOW - timedelta(days=540)   # data spans the last ~18 months

INDUSTRIES = ["Software", "Healthcare", "Finance", "Retail", "Education",
              "Manufacturing", "Logistics", "Real Estate", "Media", "Energy"]
SOURCES = ["website", "referral", "social_media", "email_campaign", "event", "cold_call", "other"]
SOURCE_W = [30, 15, 15, 15, 10, 10, 5]
LEAD_STATUS = ["new", "contacted", "qualified", "converted", "lost"]
LEAD_STATUS_W = [25, 20, 10, 30, 15]
PRODUCTS = ["CRM License", "Analytics Suite", "Support Plan", "Onboarding Package",
            "Cloud Hosting", "Training Program", "API Access", "Premium Upgrade"]
ACT_TYPES = ["call", "email", "meeting", "note", "task"]
ACT_SUBJECTS = {
    "call": ["Intro call", "Follow-up call", "Pricing discussion"],
    "email": ["Sent brochure", "Follow-up email", "Proposal sent"],
    "meeting": ["Product demo", "Kick-off meeting", "Quarterly review"],
    "note": ["Left voicemail", "Customer feedback", "Internal note"],
    "task": ["Prepare quote", "Send contract", "Schedule demo"],
}


def rand_dt(start, end):
    """Random datetime between start and end (returns start if range is empty)."""
    if end <= start:
        return start
    return start + timedelta(seconds=random.randint(0, int((end - start).total_seconds())))


def clean_email(first, last, n, domain="example.com"):
    base = re.sub(r"[^a-z0-9.]", "", f"{first}.{last}".lower())
    return f"{base}.{n}@{domain}"


def insert_batches(cur, sql, rows, size=500):
    for i in range(0, len(rows), size):
        cur.executemany(sql, rows[i:i + size])


def main():
    db_name = os.getenv("DB_NAME", "crm_db")
    print(f"This will DELETE all existing data in '{db_name}' (except pipeline stages).")
    if input("Type 'yes' to continue: ").strip().lower() != "yes":
        print("Cancelled.")
        return

    try:
        conn = mysql.connector.connect(
            host=os.getenv("DB_HOST", "localhost"),
            port=int(os.getenv("DB_PORT", 3306)),
            user=os.getenv("DB_USER", "root"),
            password=os.getenv("DB_PASSWORD", ""),
            database=db_name,
        )
    except mysql.connector.Error as e:
        print(f"Could not connect to MySQL: {e}")
        return

    cur = conn.cursor()

    # ---------- Clear old data ----------
    cur.execute("SET FOREIGN_KEY_CHECKS = 0")
    for t in ["audit_log", "activities", "opportunities", "customers",
              "contacts", "leads", "companies", "users"]:
        cur.execute(f"TRUNCATE TABLE {t}")
    cur.execute("SET FOREIGN_KEY_CHECKS = 1")

    # ---------- Users (id 1 = admin, rest = reps) ----------
    users = []
    for uid in range(1, N_USERS + 1):
        users.append((uid, fake.name(), f"user{uid}@crm-demo.com",
                      "admin" if uid == 1 else "rep", True, START))
    insert_batches(cur, "INSERT INTO users (user_id, full_name, email, role, is_active, created_at) "
                        "VALUES (%s,%s,%s,%s,%s,%s)", users)
    rep_ids = list(range(2, N_USERS + 1))

    # ---------- Companies ----------
    companies, company_names = [], {}
    for cid in range(1, N_COMPANIES + 1):
        name = fake.company()
        company_names[cid] = name
        companies.append((cid, name, random.choice(INDUSTRIES), f"https://www.company{cid}.com",
                          fake.city(), fake.country(), rand_dt(START, NOW)))
    insert_batches(cur, "INSERT INTO companies (company_id, name, industry, website, city, country, created_at) "
                        "VALUES (%s,%s,%s,%s,%s,%s,%s)", companies)

    # ---------- Leads ----------
    leads, lead_info = [], {}
    for lid in range(1, N_LEADS + 1):
        first, last = fake.first_name(), fake.last_name()
        created = rand_dt(START, NOW - timedelta(days=2))
        status = random.choices(LEAD_STATUS, LEAD_STATUS_W)[0]
        owner = random.choice(rep_ids)
        email = clean_email(first, last, lid)
        lead_info[lid] = dict(first=first, last=last, email=email, created=created,
                              status=status, owner=owner)
        leads.append((lid, f"{first} {last}", email, fake.phone_number()[:30],
                      fake.company(), random.choices(SOURCES, SOURCE_W)[0],
                      status, owner, created))
    insert_batches(cur, "INSERT INTO leads (lead_id, full_name, email, phone, company_name, source, "
                        "status, owner_id, created_at) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)", leads)

    # ---------- Contacts (converted leads + direct contacts) ----------
    contacts, contact_info, cid_seq = [], {}, 0
    for lid, info in lead_info.items():
        if info["status"] != "converted":
            continue
        cid_seq += 1
        created = min(info["created"] + timedelta(days=random.randint(1, 30)), NOW)
        company = random.randint(1, N_COMPANIES)
        contact_info[cid_seq] = dict(created=created, company=company, owner=info["owner"])
        contacts.append((cid_seq, lid, company, f"{info['first']} {info['last']}", info["email"],
                         fake.phone_number()[:30], fake.job()[:100], info["owner"], created))
    for n in range(N_DIRECT_CONTACTS):
        cid_seq += 1
        first, last = fake.first_name(), fake.last_name()
        created = rand_dt(START, NOW - timedelta(days=2))
        company = random.randint(1, N_COMPANIES)
        owner = random.choice(rep_ids)
        contact_info[cid_seq] = dict(created=created, company=company, owner=owner)
        contacts.append((cid_seq, None, company, f"{first} {last}",
                         clean_email(first, last, cid_seq, "contacts.example.com"),
                         fake.phone_number()[:30], fake.job()[:100], owner, created))
    insert_batches(cur, "INSERT INTO contacts (contact_id, lead_id, company_id, full_name, email, phone, "
                        "job_title, owner_id, created_at) VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s)", contacts)

    # ---------- Customers (about 60% of contacts) ----------
    customers, customer_info, cust_seq = [], {}, 0
    for contact_id, info in contact_info.items():
        if random.random() > 0.6:
            continue
        cust_seq += 1
        since = min(info["created"] + timedelta(days=random.randint(1, 45)), NOW)
        status = random.choices(["active", "inactive", "churned"], [75, 15, 10])[0]
        customer_info[cust_seq] = dict(since=since, owner=info["owner"], company=info["company"])
        customers.append((cust_seq, contact_id, info["company"], info["owner"],
                          since.date(), status, since))
    insert_batches(cur, "INSERT INTO customers (customer_id, contact_id, company_id, owner_id, "
                        "customer_since, status, created_at) VALUES (%s,%s,%s,%s,%s,%s,%s)", customers)

    # ---------- Opportunities ----------
    cur.execute("SELECT stage_id, is_closed FROM opportunity_stages ORDER BY stage_order")
    stages = cur.fetchall()
    stage_ids = [s[0] for s in stages]
    closed = {s[0]: bool(s[1]) for s in stages}
    stage_w = [20, 20, 20, 25, 15]   # New, Qualified, Proposal, Won, Lost

    opps, opp_info, opp_seq = [], {}, 0
    for cust_id, info in customer_info.items():
        for _ in range(random.choices([1, 2, 3, 4, 5], [35, 30, 20, 10, 5])[0]):
            opp_seq += 1
            created = rand_dt(info["since"], NOW)
            stage = random.choices(stage_ids, stage_w)[0]
            if closed[stage]:
                close_date = rand_dt(created, NOW).date()
            else:
                close_date = (NOW + timedelta(days=random.randint(7, 120))).date()
            amount = round(random.lognormvariate(8.5, 1.0), 2)   # skewed: many small, few large
            title = f"{random.choice(PRODUCTS)} - {company_names[info['company']]}"[:150]
            opp_info[opp_seq] = dict(created=created, owner=info["owner"])
            opps.append((opp_seq, cust_id, stage, info["owner"], title, amount, close_date, created))
    insert_batches(cur, "INSERT INTO opportunities (opp_id, customer_id, stage_id, owner_id, title, "
                        "amount, close_date, created_at) VALUES (%s,%s,%s,%s,%s,%s,%s,%s)", opps)

    # ---------- Activities ----------
    acts = []
    kinds = ["lead", "contact", "customer", "opp"]
    kind_w = [35, 25, 20, 20]
    for aid in range(1, N_ACTIVITIES + 1):
        kind = random.choices(kinds, kind_w)[0]
        lead_id = contact_id = customer_id = opp_id = None
        if kind == "lead":
            lead_id = random.choice(list(lead_info))
            src = lead_info[lead_id]; start = src["created"]
        elif kind == "contact":
            contact_id = random.choice(list(contact_info))
            src = contact_info[contact_id]; start = src["created"]
        elif kind == "customer":
            customer_id = random.choice(list(customer_info))
            src = customer_info[customer_id]; start = src["since"]
        else:
            opp_id = random.choice(list(opp_info))
            src = opp_info[opp_id]; start = src["created"]
        a_type = random.choice(ACT_TYPES)
        acts.append((aid, a_type, random.choice(ACT_SUBJECTS[a_type]), fake.sentence(),
                     rand_dt(start, NOW), src["owner"],
                     lead_id, contact_id, customer_id, opp_id))
    insert_batches(cur, "INSERT INTO activities (activity_id, activity_type, subject, notes, activity_date, "
                        "user_id, lead_id, contact_id, customer_id, opp_id) "
                        "VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)", acts)

    conn.commit()

    # ---------- Summary ----------
    print("\nSeed complete. Row counts:")
    for t in ["users", "companies", "leads", "contacts", "customers",
              "opportunity_stages", "opportunities", "activities"]:
        cur.execute(f"SELECT COUNT(*) FROM {t}")
        print(f"  {t:<20} {cur.fetchone()[0]}")
    cur.close()
    conn.close()


if __name__ == "__main__":
    main()
