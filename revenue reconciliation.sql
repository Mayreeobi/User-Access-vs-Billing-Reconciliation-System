USE ProjectDB

/*Post-Load Validation in SQL*/
-- Check counts
SELECT COUNT(*) AS total_users FROM dbo.user_accounts;
SELECT COUNT(*) AS total_subscribers FROM dbo.billing_subscriptions;
GO

-- ============================================================================
-- SECTION 1: BASIC EXPLORATION
-- ============================================================================

-- Query 1.1: Count users by account status
SELECT 
    account_status,
    COUNT(*) AS user_count,
    ROUND(
        COUNT(*) * 100.0 / (SELECT COUNT(*) FROM dbo.user_accounts), 
        2
    ) AS percentage
FROM dbo.user_accounts
GROUP BY account_status
ORDER BY user_count DESC;
GO


-- Query 1.2: Count subscriptions by status
SELECT 
    status,
    COUNT(*) AS subscription_count,
    SUM(billing_amount) AS total_monthly_revenue
FROM dbo.billing_subscriptions
GROUP BY status
ORDER BY total_monthly_revenue DESC;
GO


-- Query 1.3: User distribution by plan type
SELECT 
    plan_type,
    COUNT(*) AS user_count,
    COUNT(CASE WHEN account_status = 'active' THEN 1 END) AS active_users
FROM dbo.user_accounts
GROUP BY plan_type
ORDER BY user_count DESC;
GO


-- ============================================================================
-- SECTION 2: RECONCILIATION VIEWS
-- ============================================================================

-- View 1: Free Riders (Active paid users without billing)
DROP VIEW IF EXISTS dbo.v_free_riders;
GO

CREATE VIEW dbo.v_free_riders AS
SELECT 
    u.user_id,
    u.email,
    u.account_status,
    u.plan_type,
    u.features_enabled,
    u.signup_date,
    u.last_login,
    'Free Rider - No Billing' AS issue_type,
    CASE u.plan_type
        WHEN 'Starter' THEN 29
        WHEN 'Pro' THEN 99
        WHEN 'Enterprise' THEN 299
        ELSE 0
    END AS monthly_revenue_loss
FROM dbo.user_accounts u
LEFT JOIN dbo.billing_subscriptions b 
    ON u.user_id = b.user_id
    AND b.status IN ('active', 'trialing', 'past_due')
WHERE u.account_status = 'active'
  AND u.plan_type <> 'Free'
  AND b.subscription_id IS NULL;
GO


-- View 2: Ghost Subscriptions (Billing without user account)
DROP VIEW IF EXISTS dbo.v_ghost_subscriptions;
GO

CREATE VIEW dbo.v_ghost_subscriptions AS
SELECT 
    b.subscription_id,
    b.customer_email,
    b.user_id,
    b.[plan],
    b.status,
    b.billing_amount,
    b.start_date,
    b.current_period_end,
    'Ghost Subscription - No User' AS issue_type,
    b.billing_amount AS monthly_revenue_impact
FROM dbo.billing_subscriptions b
LEFT JOIN dbo.user_accounts u 
    ON b.user_id = u.user_id
WHERE b.status IN ('active', 'trialing', 'past_due')
  AND u.user_id IS NULL;
GO


-- View 3: Plan Mismatches (Different plan in app vs billing)
DROP VIEW IF EXISTS dbo.v_plan_mismatches;
GO

CREATE VIEW dbo.v_plan_mismatches AS
SELECT 
    u.user_id,
    u.email,
    u.plan_type AS user_plan,
    b.[plan] AS billing_plan,
    u.account_status,
    b.status AS billing_status,
    b.billing_amount,
    CASE u.plan_type
        WHEN 'Starter' THEN 29
        WHEN 'Pro' THEN 99
        WHEN 'Enterprise' THEN 299
        ELSE 0
    END AS should_be_charged,
    CASE 
        WHEN u.plan_type = 'Starter' AND b.billing_amount < 29 THEN 'Under-charging'
        WHEN u.plan_type = 'Pro' AND b.billing_amount < 99 THEN 'Under-charging'
        WHEN u.plan_type = 'Enterprise' AND b.billing_amount < 299 THEN 'Under-charging'
        WHEN u.plan_type = 'Starter' AND b.billing_amount > 29 THEN 'Over-charging'
        WHEN u.plan_type = 'Pro' AND b.billing_amount > 99 THEN 'Over-charging'
        WHEN u.plan_type = 'Enterprise' AND b.billing_amount > 299 THEN 'Over-charging'
        ELSE 'Over-delivering'
    END AS issue_type,
    ABS(
        b.billing_amount -
        CASE u.plan_type
            WHEN 'Starter' THEN 29
            WHEN 'Pro' THEN 99
            WHEN 'Enterprise' THEN 299
            ELSE 0
        END
    ) AS monthly_revenue_impact
FROM dbo.user_accounts u
INNER JOIN dbo.billing_subscriptions b 
    ON u.user_id = b.user_id
WHERE u.plan_type <> 'Free'
  AND b.status IN ('active', 'trialing')
  AND u.plan_type <> b.[plan];
GO


-- View 4: Status Mismatches (Active user but canceled/failed billing)
DROP VIEW IF EXISTS dbo.v_status_mismatches;
GO

CREATE VIEW dbo.v_status_mismatches AS
SELECT 
    u.user_id,
    u.email,
    u.account_status AS user_status,
    u.plan_type,
    u.last_login,
    b.subscription_id,
    b.status AS billing_status,
    b.billing_amount,
    CASE 
        WHEN u.account_status = 'active' AND b.status = 'canceled'
            THEN 'Active user - Canceled billing'
        WHEN u.account_status = 'active' AND b.status = 'past_due'
            THEN 'Active user - Payment failed'
        WHEN u.account_status IN ('inactive', 'deleted', 'suspended')
             AND b.status IN ('active', 'trialing')
            THEN 'Inactive user - Active billing'
        ELSE 'Other mismatch'
    END AS issue_type,
    b.billing_amount AS monthly_revenue_impact
FROM dbo.user_accounts u
INNER JOIN dbo.billing_subscriptions b 
    ON u.user_id = b.user_id
WHERE (
    (u.account_status = 'active' AND b.status IN ('canceled', 'past_due'))
    OR
    (u.account_status IN ('inactive', 'deleted', 'suspended')
     AND b.status IN ('active', 'trialing'))
);
GO

-- View 5: Duplicate Subscriptions (One user, multiple active subs)
DROP VIEW IF EXISTS dbo.v_duplicate_subscriptions;
GO

CREATE VIEW dbo.v_duplicate_subscriptions AS
SELECT 
    b.user_id,
    u.email,
    u.plan_type AS user_plan,
    COUNT(b.subscription_id) AS subscription_count,
    STRING_AGG(CAST(b.subscription_id AS VARCHAR(50)), ',') AS subscription_ids,
    SUM(b.billing_amount) AS total_billing_amount,
    'Duplicate Subscriptions' AS issue_type,
    SUM(b.billing_amount) - MAX(b.billing_amount) AS monthly_overcharge
FROM dbo.billing_subscriptions b
INNER JOIN dbo.user_accounts u 
    ON b.user_id = u.user_id
WHERE b.status IN ('active', 'trialing', 'past_due')
GROUP BY b.user_id, u.email, u.plan_type
HAVING COUNT(b.subscription_id) > 1;
GO


-- View 6: Free Users with Billing (Should be canceled)
DROP VIEW IF EXISTS dbo.v_free_with_billing;
GO

CREATE VIEW dbo.v_free_with_billing AS
SELECT 
    u.user_id,
    u.email,
    u.plan_type,
    u.account_status,
    b.subscription_id,
    b.[plan] AS billing_plan,
    b.status AS billing_status,
    b.billing_amount,
    'Free Plan with Active Billing' AS issue_type,
    b.billing_amount AS monthly_revenue_impact
FROM dbo.user_accounts u
INNER JOIN dbo.billing_subscriptions b 
    ON u.user_id = b.user_id
WHERE u.plan_type = 'Free'
  AND b.status IN ('active', 'trialing', 'past_due');
GO


-- View 7: Trial Expiration Issues
DROP VIEW IF EXISTS dbo.v_trial_issues;
GO

CREATE VIEW dbo.v_trial_issues AS
SELECT 
    u.user_id,
    u.email,
    u.plan_type,
    u.account_status,
    b.subscription_id,
    b.status AS billing_status,
    b.current_period_end,
    DATEDIFF(DAY, b.current_period_end, GETDATE()) AS days_past_end,
    'Trial Period Expired' AS issue_type,
    CASE u.plan_type
        WHEN 'Starter' THEN 29
        WHEN 'Pro' THEN 99
        WHEN 'Enterprise' THEN 299
        ELSE 0
    END AS monthly_revenue_loss
FROM dbo.user_accounts u
INNER JOIN dbo.billing_subscriptions b 
    ON u.user_id = b.user_id
WHERE b.status = 'trialing'
  AND b.current_period_end < CAST(GETDATE() AS DATE)
  AND u.account_status = 'active';
GO


-- View 8: Summary Metrics
DROP VIEW IF EXISTS dbo.v_summary_metrics;
GO

CREATE VIEW dbo.v_summary_metrics AS
SELECT 'Total Users' as metric, COUNT(*) as value FROM user_accounts
UNION ALL
SELECT 'Active Users' as metric, COUNT(*) as value FROM user_accounts WHERE account_status = 'active'
UNION ALL
SELECT 'Total Subscriptions' as metric, COUNT(*) as value FROM billing_subscriptions
UNION ALL
SELECT 'Active Subscriptions' as metric, COUNT(*) as value FROM billing_subscriptions WHERE status IN ('active', 'trialing')
UNION ALL
SELECT 'Free Riders' as metric, COUNT(*) as value FROM v_free_riders
UNION ALL
SELECT 'Ghost Subscriptions' as metric, COUNT(*) as value FROM v_ghost_subscriptions
UNION ALL
SELECT 'Plan Mismatches' as metric, COUNT(*) as value FROM v_plan_mismatches
UNION ALL
SELECT 'Status Mismatches' as metric, COUNT(*) as value FROM v_status_mismatches
UNION ALL
SELECT 'Duplicate Subscriptions' as metric, COUNT(*) as value FROM v_duplicate_subscriptions
UNION ALL
SELECT 'Free with Billing' as metric, COUNT(*) as value FROM v_free_with_billing
UNION ALL
SELECT 'Trial Period Expired' as metric, COUNT(*) as value FROM v_trial_issues;
GO

-- View 9: Revenue Impact Summary
DROP VIEW IF EXISTS dbo.v_revenue_impact;
GO

CREATE VIEW dbo.v_revenue_impact AS
SELECT 
    issue_type,
    COUNT(*) AS issue_count,
    SUM(monthly_revenue_loss) AS total_monthly_impact,
    AVG(monthly_revenue_loss) AS avg_impact_per_issue
FROM (
    SELECT issue_type, monthly_revenue_loss FROM dbo.v_free_riders
    UNION ALL
    SELECT issue_type, monthly_revenue_impact FROM dbo.v_ghost_subscriptions
    UNION ALL
    SELECT issue_type, monthly_revenue_impact FROM dbo.v_plan_mismatches
    UNION ALL
    SELECT issue_type, monthly_revenue_impact FROM dbo.v_status_mismatches
    UNION ALL
    SELECT issue_type, monthly_overcharge FROM dbo.v_duplicate_subscriptions
    UNION ALL
    SELECT issue_type, monthly_revenue_impact FROM dbo.v_free_with_billing
    UNION ALL
    SELECT issue_type, monthly_revenue_loss FROM dbo.v_trial_issues
) AS revenue_issues
GROUP BY issue_type;
GO


-- ============================================================================
-- SECTION 3: ISSUE IDENTIFICATION monthly_revenue_loss
-- ============================================================================

-- Query 3.1: Top 10 free riders by revenue loss
SELECT TOP 10 *
FROM dbo.v_free_riders
ORDER BY monthly_revenue_loss DESC;

-- Query 3.2: All ghost subscriptions with details
SELECT 
    subscription_id,
    customer_email,
    [plan],
    billing_amount,
    start_date,
    DATEDIFF(DAY, start_date, '2025-02-28') AS days_active
FROM dbo.v_ghost_subscriptions
ORDER BY billing_amount DESC;


-- Query 3.3: Plan mismatches categorized
SELECT 
    issue_type,
    COUNT(*) as count,
    SUM(monthly_revenue_impact) as total_impact
FROM v_plan_mismatches
GROUP BY issue_type
ORDER BY total_impact DESC;


-- Query 3.4: Status mismatches by severity
SELECT 
    issue_type,
    COUNT(*) as issue_count,
     CONCAT('$', FORMAT(SUM(monthly_revenue_impact), 'N0')) as total_impact,
     CONCAT('$', FORMAT(AVG(monthly_revenue_impact), 'N0')) as avg_impact
FROM v_status_mismatches
GROUP BY issue_type
ORDER BY total_impact DESC;

-- ============================================================================
-- SECTION 4: REVENUE ANALYSIS
-- ============================================================================

-- Query 4.1: Total monthly revenue at risk
SELECT 
    CONCAT('$', FORMAT(SUM(total_monthly_impact), 'N0')) AS total_monthly_at_risk,
    CONCAT('$', FORMAT(SUM(total_monthly_impact) * 12, 'N0')) AS annual_projection
FROM dbo.v_revenue_impact;


-- Query 4.2: Revenue impact by issue type (detailed)
SELECT 
    issue_type,
    issue_count,
    CONCAT('$',FORMAT(total_monthly_impact, 'N0')) AS total_monthly_impact,
    
    -- Columns 1: leakage rate
    CONCAT(CAST(ROUND(
        total_monthly_impact * 100.0 / 
        (SELECT SUM(billing_amount)
         FROM billing_subscriptions
         WHERE status IN ('active', 'trialing')),
        2
        ) AS DECIMAL(10, 2)), '%') AS leakage_rate_percentage,
    
    -- Column 2: Share of total problems
    CONCAT(
        CAST(
            ROUND(
                total_monthly_impact * 100.0 / 
                (SELECT SUM(total_monthly_impact) FROM dbo.v_revenue_impact),
                2
            ) AS DECIMAL(10, 2)
        ),
        '%'
    ) AS leakage_percentage_of_total
FROM v_revenue_impact
ORDER BY total_monthly_impact DESC;


-- Query 4.3: Expected vs actual monthly recurring revenue
SELECT 
    'Expected MRR' AS metric,
    CONCAT('$', FORMAT(SUM(CASE plan_type
        WHEN 'Starter' THEN 29
        WHEN 'Pro' THEN 99
        WHEN 'Enterprise' THEN 299
        ELSE 0
    END), 'N0')) AS amount
FROM user_accounts
WHERE account_status = 'active'
  AND plan_type <> 'Free'

UNION ALL

SELECT 
    'Actual MRR' AS metric,
    CONCAT('$', FORMAT(SUM(billing_amount), 'N0')) AS amount
FROM billing_subscriptions
WHERE status IN ('active', 'trialing');


-- Query 4.4: Revenue leakage by plan tier
SELECT 
    plan_type,
    COUNT(*) as free_rider_count,
    CONCAT('$', FORMAT(SUM(monthly_revenue_loss), 'N0')) as total_lost_revenue
FROM v_free_riders
GROUP BY plan_type
ORDER BY total_lost_revenue DESC;

-- ============================================================================
-- SECTION 5: USER HEALTH ANALYSIS
-- ============================================================================

-- Query 5.1: User health matrix (account status vs billing status)
SELECT 
    u.account_status,
    COALESCE(b.status, 'No Billing') as billing_status,
    COUNT(*) as user_count
FROM user_accounts u
LEFT JOIN billing_subscriptions b ON u.user_id = b.user_id
WHERE u.plan_type != 'Free'
GROUP BY u.account_status, COALESCE(b.status, 'No Billing')
ORDER BY u.account_status, billing_status;


-- Query 5.2: Inactive users still being billed
SELECT 
    u.user_id,
    u.email,
    u.plan_type,
    u.last_login,
    DATEDIFF(DAY, u.last_login, '2025-02-28') AS days_since_login,
    b.billing_amount
FROM dbo.user_accounts u
INNER JOIN dbo.billing_subscriptions b
    ON u.user_id = b.user_id
WHERE u.account_status = 'inactive'
  AND b.status = 'active'
ORDER BY days_since_login DESC;


-- ============================================================================
-- SECTION 6: ACTIONABLE QUERIES
-- ============================================================================

-- Query 6.1: Users who need immediate action (high value)
SELECT 
    user_id,
    email,
    issue_type,
    monthly_revenue_loss,
    'Create subscription or suspend access' as action_required,
    'Critical - High Value' as priority
FROM v_free_riders
WHERE monthly_revenue_loss >= 99
ORDER BY monthly_revenue_loss DESC;

-- Query 6.2: Quick wins (easy fixes with good impact)
SELECT 
    'Cancel Ghost Subscriptions' as action,
    COUNT(*) as affected_count,
    SUM(monthly_revenue_impact) as monthly_impact,
    'Cancel subscription and refund' as steps,
    '< 1 hour' as estimated_time
FROM v_ghost_subscriptions

UNION ALL

SELECT 
    'Fix Free Users Being Charged' as action,
    COUNT(*) as affected_count,
    SUM(monthly_revenue_impact) as monthly_impact,
    'Cancel subscription and issue full refund' as steps,
    '< 1 hour' as estimated_time
FROM v_free_with_billing

UNION ALL

SELECT 
    'Remove Duplicate Subscriptions' as action,
    COUNT(*) as affected_count,
    SUM(monthly_overcharge) as monthly_impact,
    'Cancel duplicate and issue credit' as steps,
    '< 2 hours' as estimated_time
FROM v_duplicate_subscriptions;


-- ============================================================================
-- SECTION 7: TREND ANALYSIS
-- ============================================================================

SELECT 
    'Current State' as period,
    (SELECT COUNT(*) FROM v_free_riders) as free_riders,
    (SELECT COUNT(*) FROM v_ghost_subscriptions) as ghost_subs,
    (SELECT COUNT(*) FROM v_plan_mismatches) as plan_mismatches,
    (SELECT COUNT(*) FROM v_status_mismatches) as status_mismatches,
    (SELECT COUNT(*) FROM v_free_with_billing) as free_with_billing,
    (SELECT COUNT(*) FROM v_duplicate_subscriptions) as duplicate_subscriptions,
    (SELECT COUNT(*) FROM v_trial_issues) as trial_issues;

-- ============================================================================
-- SECTION 8: EXECUTIVE SUMMARY QUERIES
-- ============================================================================

-- Query 8.1: One-page executive summary
SELECT 
    'Total Active Users' as metric,
    COUNT(*) as value,
    '' as details
FROM user_accounts 
WHERE account_status = 'active'

UNION ALL

SELECT 
    'Active Subscriptions' as metric,
    COUNT(*) as value,
    'Status: active, trialing' as details
FROM billing_subscriptions 
WHERE status IN ('active', 'trialing')

UNION ALL

SELECT 
    'Total Issues Found' as metric,
    (SELECT SUM(issue_count) FROM v_revenue_impact) as value,
    'Across 7 categories' as details

UNION ALL

SELECT 
    'Monthly Revenue at Risk' as metric,
    ROUND(SUM(total_monthly_impact), 2) as value,
    'Requires immediate action' as details
FROM v_revenue_impact

UNION ALL

SELECT 
    'Annual Revenue Projection' as metric,
    ROUND(SUM(total_monthly_impact) * 12, 2) as value,
    'If issues not resolved' as details
FROM v_revenue_impact;


-- Query 8.2: Top 5 issues by financial impact
SELECT TOP 5
    issue_type,
    issue_count,
    CONCAT('$', FORMAT(total_monthly_impact, 'N0')) AS monthly_impact,
    CONCAT('$', FORMAT(total_monthly_impact * 12, 'N0')) AS annual_impact
FROM dbo.v_revenue_impact
ORDER BY total_monthly_impact DESC;

-- ============================================================================
-- SECTION 9: DATA QUALITY CHECKS
-- ============================================================================

-- Query 9.1: Check for duplicate user IDs in issue views
SELECT 
    'Duplicate Users in Free Riders' as check_name,
    COUNT(*) - COUNT(DISTINCT user_id) as duplicate_count
FROM v_free_riders;

-- Query 9.2: Validate email formats
SELECT 
    'Invalid Email Formats' as check_name,
    COUNT(*) as invalid_count
FROM user_accounts
WHERE email NOT LIKE '%@%.%';

-- Query 9.3: Check for NULL email addresses
SELECT 'NULL Emails' AS check_name, COUNT(*) AS failing_records
FROM user_accounts
WHERE email IS NULL OR email = '';

-- Query 9.4: Check for future dates
SELECT 'Future Signup Dates' AS check_name, COUNT(*) AS failing_records
FROM user_accounts
WHERE signup_date > GETDATE();

-- Query 9.5: Check for impossible billing amounts (like $0.01 or $999,999)
SELECT 'Suspicious Billing Amounts' AS check_name, COUNT(*) AS failing_records
FROM billing_subscriptions
WHERE billing_amount < 1 OR billing_amount > 1000;


