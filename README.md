# SaaS User Access vs Billing Reconciliation System

Automated system to identify and quantify revenue leakage from mismatches between user account access and billing records.

[![SQL](https://img.shields.io/badge/SQL-SQLServer-blue)](https://github.com/Mayreeobi/Revenue-Reconciliation-System/blob/main/revenue%20reconciliation.sql)
[![Python](https://img.shields.io/badge/Python-3.8%2B-yellow)](https://github.com/Mayreeobi/Revenue-Reconciliation-System/blob/main/data%20reconcilation%20generator.ipynb)

---

## Project Overview
Built an automated reconciliation system to identify revenue leakage in SaaS businesses by comparing user access logs against billing records. This system helps finance teams quickly spot discrepancies between who has active access and who's actually being billed. 

## The Business Problem
SaaS companies often face a critical challenge: users with active system access who aren't being billed, or inactive users still being charged. According to industry research, SaaS companies lose 5-10% of monthly recurring revenue to billing errors, and manual reconciliation takes finance teams 20-40 hours per month. This system automates what typically requires a full-time analyst.

## What This Does
The system identifies seven critical types of reconciliation issues:
- **Free Riders**: Users accessing paid features without billing ($4,455/mo average loss) ($3,971/month loss)
- **Ghost Subscriptions**: Billing records without corresponding users ($2,280/month refund liability)
- **Plan Mismatches**: User's plan doesn't match their billing plan ($6,500/month impact)
- **Status Mismatches**: Active users with failed/canceled payments ($4,241/month loss)
- **Duplicate Billing**: Users charged multiple times for same service
- **Billing Errors**: Free users being charged, deleted users still billed
- **Expired Trials**: Trial periods ended but still getting paid features

## 📊 Key Results

| Metric | Value |
|--------|-------|
| Users Analyzed | 500 |
| **Categories of Problems** | 7 |
| Issues Identified | 171 |
| **Monthly Revenue at Risk** | **$21,699** |
| **Actual Monthly MRR** | **$38,455** |
| **Expected Monthly MRR** | **$60,154** |
| **Annual Revenue Exposure** | **$260,388** |

- Revenue Leakage Rate represents the percentage of billed MRR currently exposed to access and billing inconsistencies. Expected MRR reflects theoretical revenue based on active user plans, not recognized revenue.

---

## 🛠️ Tech Stack

- **Python (3.8+)** – Synthetic SaaS data generation & ETL
- **SQL Server** – Reconciliation logic, views, revenue impact calculations  
- **Power BI** – Executive dashboard *(in progress)*
- **ETL pipeline development (Python → SQL → Power BI)
> ⚠️ Dashboard will be added once finalized.

---

## 🔍 Reconciliation Logic (Example)

**Free Riders — Active users with paid access but no active billing subscription**

**SQL Logic:**
```sql
SELECT u.*
FROM user_accounts u
LEFT JOIN billing_subscriptions b ON u.user_id = b.user_id
WHERE u.account_status = 'active'
  AND u.plan_type != 'Free'
  AND b.subscription_id IS NULL
```

**Business Impact:** Direct revenue loss of expected subscription fee

**Typical Causes:**
- Payment method declined but access not revoked
- Trial conversion failed
- Manual provisioning without billing setup
- Integration bug between systems

**Recommended Action:** Create subscription or suspend access within 24 hours

---


## 📊 SQL Views Explanation

**v_free_riders:** Lists all users accessing paid features without billing. Calculates expected monthly revenue based on their plan tier.

**v_ghost_subscriptions:** Identifies billing records without user accounts. Shows refund liability and wasted processing fees.

**v_plan_mismatches:** Compares user plan vs billing plan. Calculates over/under charging amount and categorizes as revenue loss or customer service issue.

**v_status_mismatches:** Finds users where account status and billing status don't align. Critical for identifying access control failures.

**v_duplicate_subscriptions:** Detects users with multiple active subscriptions. Shows total overcharge amount.

**v_free_with_billing:** Lists Free tier users being charged. 100% refund candidates.

**v_trial_issues:** Lists Trials that ended but user still has active access.

**v_summary_metrics:** High-level KPIs for dashboard: total users, subscriptions, issue counts.

**v_revenue_impact:** Aggregates monthly revenue impact by issue type. Used for prioritization.

---

## 📈 Dashboard (Planned Features)
- Total monthly revenue at risk
- Revenue leakage by issue type
- User access vs billing health matrix
- Priority ranking for revenue recovery
- Drill-down table for operations teams
---

## 💰 Findings (From Generated Data)

```
REVENUE IMPACT SUMMARY
════════════════════════════════════════════════════

Issue Type                                        Count    Monthly Impact   
───────────────────────────────────────────────────────────────────────
Free Riders (No billing)                          29      $3,971           
Status Mismatches (Active User-Payment failed)    29      $4,241           
Status Mismatches (Inactive user-Active billing)  20      $2,430
Plan Mismatches (Over-charging)                   20      $3,250           
Plan Mismatches (Under-charging)                  19      $3,250           
Ghost Subscriptions (No user)                     20      $2,280          
Duplicate Subscriptions                           18      $1,012           
Trial Period Expired                              15      $1,265
Free with Billing                                  1      $0              
─────────────────────────────────────────────────────────────────────────
TOTAL                                             171     $21,699/month
                                                          $260,388/year

Quick Wins (Fix in < 1 week):
✓ Cancel ghost subscriptions: $2,280/mo recovered
✓ Remove duplicate subs: $1,012/mo + improve customer satisfaction

High-Value Fixes (Fix in < 1 month):
✓ Create billing for free riders: $3,971/mo revenue capture
✓ Update plan mismatches: $6,500/mo revenue optimization
✓ Enforce payment failures: $/mo + reduce bad debt
```
---

## Business Rules & Assumptions

### Expected System Behavior

**Correct States:**
1. Active user + Active billing + Matching plans = ✅ Healthy
2. Free user + No billing = ✅ Healthy  
3. Deleted user + No billing = ✅ Healthy
4. Inactive user + Canceled billing = ✅ Healthy

### Grace Periods & Edge Cases

**Payment Failures:**
- Grace period: 3 days past due before suspension
- Users in "past_due" status are flagged but may be in grace period

**Trial Conversions:**
- Trials that just ended (< 24 hours) may be in processing
- Only flag trials expired > 1 day

**Account Deletions:**
- Recent deletions (< 7 days) may have pending cancellations
- Ghost subs from deletions > 7 days are definite issues

---

## Recommended Actions by Priority

### Priority 1: Immediate (Fix a Day)
- Free users being charged → Cancel + refund
- Deleted users with active billing → Cancel + refund
- Duplicate subscriptions → Cancel duplicate + credit

**Why:** Legal/compliance risk, potential chargebacks

### Priority 2: Critical (Fix a Week)
- Free riders (high-value) → Create subscription or suspend
- Status mismatches (payment failures) → Enforce suspension
- Ghost subscriptions → Cancel + refund

**Why:** Direct revenue loss, growing technical debt

### Priority 3: Important (Fix a Month)
- Plan mismatches (under-charging) → Update billing
- Plan mismatches (over-charging) → Credit + adjust
- Expired trials → Convert or suspend

**Why:** Revenue optimization, customer satisfaction

### Priority 4: Monitoring (Track & Prevent)
- Set up alerts for new issues
- Implement automated checks at signup/upgrade
- Add reconciliation step to nightly jobs
- Dashboard review in weekly ops meetings

---
## 🔗 Project Assets

- **SQL Queries:**  
  https://github.com/Mayreeobi/Revenue-Reconciliation-System/blob/main/revenue%20reconciliation.sql

- **Python Data Generator:**  
  https://github.com/Mayreeobi/Revenue-Reconciliation-System/blob/main/data%20reconcilation%20generator.ipynb

---
## 📂 Project Structure

```
saas-user-billing-reconciliation/
│
├── README.md                          # This file
├── data/
│   └── generate_data.py             # Creates synthetic dataset
│
├── sql/
│   ├── create_views.sql              # Reconciliation views
│   └── sample_queries.sql            # Example analyses
│
└── Power BI/
    └── Dashboard                     # Dashboard   
```

---
