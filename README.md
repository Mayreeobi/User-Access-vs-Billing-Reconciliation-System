# SaaS User Access vs Billing Reconciliation System

Automated system to identify and quantify revenue leakage from mismatches between user account access and billing records.

[![Tableau Public](https://img.shields.io/badge/Tableau-Live%20Dashboard-blue)](your-tableau-link)
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

### 📊 Key Results

| Metric | Value |
|--------|-------|
| **Total Monthly Revenue at Risk** | **$21,699** |
| **Annual Projection** | **$260,388** |
| **Users Analyzed** | 500 |
| **Issues Identified** | 171 |
| **Categories of Problems** | 7 |

- Revenue Leakage Rate represents the percentage of billed MRR currently exposed to access and billing inconsistencies. Expected MRR reflects theoretical revenue based on active user plans, not recognized revenue.
---

## 🛠️ Technologies & Skills Demonstrated

**Technical:**
- Python (Pandas, data generation, ETL)
- Advanced SQL queries (Joins, window functions, reconciliation logic)
- Data quality validation & anomaly detection
- ETL pipeline development (Python → SQL → Power BI)

**Visualization:**
- Power BI (interactive dashboards, DAX)
- Data storytelling
- Executive-level reporting
- Revenue leakage analysis (MRR-focused)

**Analytical & Business:**
- SaaS metrics & operations
- Revenue leakage analysis & financial modeling
- Root cause analysis for system discrepancies
- Business logic implementation
- Access control & billing systems

---

## 📂 Project Structure

```
saas-user-billing-reconciliation/
│
├── README.md                          # This file
├── data/
│   └── README.md                     # Data dictionary
│
├── scripts/
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

## 🔍 Reconciliation Logic

### Issue Type 1: Free Riders
**Definition:** Active users with paid plan access but no active billing subscription

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

### Issue Type 2: Ghost Subscriptions
**Definition:** Active billing subscriptions without corresponding user accounts

**SQL Logic:**
```sql
SELECT b.*
FROM billing_subscriptions b
LEFT JOIN user_accounts u ON b.user_id = u.user_id
WHERE b.status IN ('active', 'trialing', 'past_due')
  AND u.user_id IS NULL
```

**Business Impact:** Potential refund liability + reputational risk

**Typical Causes:**
- User deleted account but cancellation didn't process
- Data sync failure between systems
- Account merge/migration issues
- Orphaned records from data cleanup

**Recommended Action:** Cancel subscription and issue prorated refund

---

### Issue Type 3: Plan Mismatches
**Definition:** User's access level doesn't match their billing plan

**Example Scenarios:**
- User has Pro access but billed for Starter (revenue loss)
- User has Starter access but billed for Pro (overcharging)
- User upgraded in app but billing not updated

**SQL Logic:**
```sql
SELECT u.user_id, u.plan_type,
       b.[plan] as billing_plan
FROM user_accounts u
INNER JOIN billing_subscriptions b ON u.user_id = b.user_id
WHERE u.plan_type != b.[plan]
  AND u.plan_type != 'Free'
```

**Business Impact:** Revenue loss (under-charging) or customer dissatisfaction (over-charging)

**Recommended Action:** 
- Under-charging: Update billing, document grandfathering if needed
- Over-charging: Issue credit and adjust billing immediately

---

### Issue Type 4: Status Mismatches
**Definition:** User account status doesn't align with billing status

**Critical Combinations:**
- Active user + Canceled billing = Free rider
- Active user + Past due billing = Payment failure not enforced
- Deleted user + Active billing = Billing not canceled
- Inactive user + Active billing = Paying for no usage

**SQL Logic:**
```sql
SELECT u.user_id, u.account_status, b.status
FROM user_accounts u
INNER JOIN billing_subscriptions b ON u.user_id = b.user_id
WHERE (u.account_status = 'active' AND b.status IN ('canceled', 'past_due'))
   OR (u.account_status IN ('inactive', 'deleted') AND b.status = 'active')
```

**Recommended Actions:**
- Active/Canceled: Suspend access
- Active/Past due: Lock account after grace period
- Deleted/Active: Cancel subscription and refund
- Inactive/Active: Offer pause or cancellation

---

### Issue Type 5: Duplicate Subscriptions
**Definition:** Single user with multiple active subscriptions

**SQL Logic:**
```sql
SELECT user_id, COUNT(*) as subscription_count
FROM billing_subscriptions
WHERE status IN ('active', 'trialing')
GROUP BY user_id
HAVING COUNT(*) > 1
```

**Business Impact:** Customer overcharged, potential chargeback risk

**Typical Causes:**
- User changed payment method (created new sub instead of updating)
- Plan upgrade created new subscription without canceling old
- Manual billing intervention
- System bug during checkout

**Recommended Action:** Cancel duplicate, issue credit, keep highest-tier subscription

---

### Issue Type 6: Free Plans with Billing
**Definition:** Users on Free plan with active billing subscriptions

**SQL Logic:**
```sql
SELECT u.user_id, b.billing_amount
FROM user_accounts u
INNER JOIN billing_subscriptions b ON u.user_id = b.user_id
WHERE u.plan_type = 'Free'
  AND b.status = 'active'
```

**Business Impact:** Charging customers for free tier (immediate refund risk)

**Recommended Action:** Cancel subscription immediately, issue full refund

---

### Issue Type 7: Trial Expiration Issues
**Definition:** Trials that ended but user still has active access

**SQL Logic:**
```sql
SELECT u.user_id, b.current_period_end
FROM user_accounts u
INNER JOIN billing_subscriptions b ON u.user_id = b.user_id
WHERE b.status = 'trialing'
  AND b.current_period_end < CAST(GETDATE() AS DATE)
  AND u.account_status = 'active'
```

**Business Impact:** Free access beyond trial period (revenue loss)

**Recommended Action:** Convert to paid or suspend access

---

## 📊 SQL Views Explanation

### v_free_riders
Lists all users accessing paid features without billing. Calculates expected monthly revenue based on their plan tier.

### v_ghost_subscriptions  
Identifies billing records without user accounts. Shows refund liability and wasted processing fees.

### v_plan_mismatches
Compares user plan vs billing plan. Calculates over/under charging amount and categorizes as revenue loss or customer service issue.

### v_status_mismatches
Finds users where account status and billing status don't align. Critical for identifying access control failures.

### v_duplicate_subscriptions
Detects users with multiple active subscriptions. Shows total overcharge amount.

### v_free_with_billing
Lists Free tier users being charged. 100% refund candidates.

### v_trial_issues
Lists Trials that ended but user still has active access.

### v_summary_metrics
High-level KPIs for dashboard: total users, subscriptions, issue counts.

### v_revenue_impact
Aggregates monthly revenue impact by issue type. Used for prioritization.

---

## 📈 Dashboard Features

### Executive Summary
- Total monthly revenue at risk (big number, red)
- Count of each issue type
- Active users vs active subscriptions comparison
- Health score gauge (% of users correctly configured)

### Free Riders Analysis
- Top 10 users by revenue loss
- Breakdown by plan type
- Days since last login (identify inactive free riders)
- Signup date cohort analysis

### User Health Matrix
- Heatmap: Account Status vs Billing Status
- Color-coded problem areas
- Drill-down to user list
- Quick filters for action prioritization

### Revenue Impact Summary
- Stacked bar chart by issue type
- Monthly and annual projections
- Percentage of total revenue
- Priority ranking for fixes

### Detailed Investigation Table
- Filterable list of all issues
- Shows user details, issue type, impact
- "Action Required" field with recommendations
- Exportable for operations team

---

## 💰 Sample Findings (From Generated Data)

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

## 🎓 Business Rules & Assumptions

### Expected System Behavior

**Correct States:**
1. Active user + Active billing + Matching plans = ✅ Healthy
2. Free user + No billing = ✅ Healthy  
3. Deleted user + No billing = ✅ Healthy
4. Inactive user + Canceled billing = ✅ Healthy

**Problem States:**
1. Active user + No billing + Paid plan = ❌ Free rider
2. Active user + Canceled billing = ❌ Payment not enforced
3. Active billing + No user = ❌ Ghost subscription
4. User plan ≠ Billing plan = ❌ Plan mismatch
5. Multiple active subs for same user = ❌ Duplicate billing

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

## 🎯 Recommended Actions by Priority

### Priority 1: Immediate (Fix Today)
- Free users being charged → Cancel + refund
- Deleted users with active billing → Cancel + refund
- Duplicate subscriptions → Cancel duplicate + credit

**Why:** Legal/compliance risk, potential chargebacks

### Priority 2: Critical (Fix This Week)
- Free riders (high-value) → Create subscription or suspend
- Status mismatches (payment failures) → Enforce suspension
- Ghost subscriptions → Cancel + refund

**Why:** Direct revenue loss, growing technical debt

### Priority 3: Important (Fix This Month)
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

- **SQL Queries:**  [https://github.com/Mayreeobi/Revenue-Reconciliation-System/blob/main/revenue%20reconciliation.sql]

- **Python Data Generator:**  (https://github.com/Mayreeobi/Revenue-Reconciliation-System/blob/main/data%20reconcilation%20generator.ipynb)

---
