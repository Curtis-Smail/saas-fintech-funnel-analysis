USE saas_funnel;

-- Subscription status is defined using the subscriptions table.
-- Orphaned funnel events are excluded through joins to users.

-- Q1. Sequential funnel stage reach and conversion rates
--     Stages 1-7 require a complete sequential prefix.
--     Subscribed users are sourced from the subscriptions table.
WITH user_stages AS (
    SELECT DISTINCT
        fe.user_id,
        FIELD(fe.event_type, 'signup', 'email_verified', 'kyc_submitted', 'kyc_approved',
              'bank_linked', 'first_deposit', 'plan_selected', 'subscribed') AS stage_order
    FROM funnel_events fe
    JOIN users u ON fe.user_id = u.user_id
    WHERE fe.event_type <> 'subscribed'
),
ranked AS (
    SELECT
        user_id,
        stage_order,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY stage_order) AS rn
    FROM user_stages
),
prefix_stage_counts AS (
    SELECT stage_order, COUNT(DISTINCT user_id) AS users_reached
    FROM ranked
    WHERE stage_order = rn
    GROUP BY stage_order
),
combined AS (
    SELECT stage_order, users_reached FROM prefix_stage_counts
    UNION ALL
    SELECT 8, (SELECT COUNT(DISTINCT user_id) FROM subscriptions)
)
SELECT
    CASE stage_order
        WHEN 1 THEN 'signup' WHEN 2 THEN 'email_verified' WHEN 3 THEN 'kyc_submitted'
        WHEN 4 THEN 'kyc_approved' WHEN 5 THEN 'bank_linked' WHEN 6 THEN 'first_deposit'
        WHEN 7 THEN 'plan_selected' WHEN 8 THEN 'subscribed'
    END AS event_type,
    users_reached,
    ROUND(users_reached / FIRST_VALUE(users_reached) OVER (ORDER BY stage_order) * 100, 2) AS pct_of_signups,
    ROUND(users_reached / LAG(users_reached) OVER (ORDER BY stage_order) * 100, 2) AS pct_of_prev_stage
FROM combined
ORDER BY stage_order;

-- Q2. Sequential funnel drop-off by stage
--     (same sequential-prefix + subscriptions-table logic as Q1)
WITH user_stages AS (
    SELECT DISTINCT
        fe.user_id,
        FIELD(fe.event_type, 'signup', 'email_verified', 'kyc_submitted', 'kyc_approved',
              'bank_linked', 'first_deposit', 'plan_selected', 'subscribed') AS stage_order
    FROM funnel_events fe
    JOIN users u ON fe.user_id = u.user_id
    WHERE fe.event_type <> 'subscribed'
),
ranked AS (
    SELECT
        user_id,
        stage_order,
        ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY stage_order) AS rn
    FROM user_stages
),
prefix_stage_counts AS (
    SELECT stage_order, COUNT(DISTINCT user_id) AS users_reached
    FROM ranked
    WHERE stage_order = rn
    GROUP BY stage_order
),
combined AS (
    SELECT stage_order, users_reached FROM prefix_stage_counts
    UNION ALL
    SELECT 8, (SELECT COUNT(DISTINCT user_id) FROM subscriptions)
),
stage_drop AS (
    SELECT
        CASE stage_order
            WHEN 1 THEN 'signup' WHEN 2 THEN 'email_verified' WHEN 3 THEN 'kyc_submitted'
            WHEN 4 THEN 'kyc_approved' WHEN 5 THEN 'bank_linked' WHEN 6 THEN 'first_deposit'
            WHEN 7 THEN 'plan_selected' WHEN 8 THEN 'subscribed'
        END AS to_stage,
        LAG(CASE stage_order
            WHEN 1 THEN 'signup' WHEN 2 THEN 'email_verified' WHEN 3 THEN 'kyc_submitted'
            WHEN 4 THEN 'kyc_approved' WHEN 5 THEN 'bank_linked' WHEN 6 THEN 'first_deposit'
            WHEN 7 THEN 'plan_selected' WHEN 8 THEN 'subscribed'
        END) OVER (ORDER BY stage_order) AS from_stage,
        LAG(users_reached) OVER (ORDER BY stage_order) AS prev_users,
        users_reached AS curr_users
    FROM combined
)
SELECT
    from_stage,
    to_stage,
    prev_users - curr_users AS users_lost,
    ROUND((prev_users - curr_users) / prev_users * 100, 2) AS pct_lost
FROM stage_drop
WHERE from_stage IS NOT NULL
ORDER BY pct_lost DESC;

-- Q3a. Overall signup-to-subscription time
--      Restricted to users with a matching subscription record.
--      (joins to subscriptions rather than users; no orphan exists there).
WITH signup_times AS (
    SELECT fe.user_id, MIN(fe.event_timestamp) AS signup_time
    FROM funnel_events fe
    JOIN users u ON fe.user_id = u.user_id
    WHERE fe.event_type = 'signup'
    GROUP BY fe.user_id
),
subscribed_times AS (
    SELECT fe.user_id, MIN(fe.event_timestamp) AS subscribed_time
    FROM funnel_events fe
    JOIN subscriptions s ON fe.user_id = s.user_id
    WHERE fe.event_type = 'subscribed'
    GROUP BY fe.user_id
)
SELECT
    ROUND(AVG(TIMESTAMPDIFF(HOUR, s.signup_time, sub.subscribed_time)) / 24, 2) AS avg_days_to_convert,
    ROUND(MIN(TIMESTAMPDIFF(HOUR, s.signup_time, sub.subscribed_time)) / 24, 2) AS fastest_days,
    ROUND(MAX(TIMESTAMPDIFF(HOUR, s.signup_time, sub.subscribed_time)) / 24, 2) AS slowest_days
FROM signup_times s
JOIN subscribed_times sub ON s.user_id = sub.user_id
WHERE sub.subscribed_time >= s.signup_time;

-- Q3b. Average time between consecutive funnel stages
--      Only genuinely adjacent stages are included.
WITH user_stage_times AS (
    SELECT
        fe.user_id,
        fe.event_type,
        MIN(fe.event_timestamp) AS stage_time,
        FIELD(fe.event_type, 'signup', 'email_verified', 'kyc_submitted', 'kyc_approved',
              'bank_linked', 'first_deposit', 'plan_selected', 'subscribed') AS stage_order
    FROM funnel_events fe
    JOIN users u ON fe.user_id = u.user_id
    GROUP BY fe.user_id, fe.event_type
),
consecutive_stage_pairs AS (
    SELECT
        user_id,
        event_type,
        stage_time,
        stage_order,
        LAG(event_type) OVER (PARTITION BY user_id ORDER BY stage_order) AS prev_stage,
        LAG(stage_time) OVER (PARTITION BY user_id ORDER BY stage_order) AS prev_stage_time,
        LAG(stage_order) OVER (PARTITION BY user_id ORDER BY stage_order) AS prev_stage_order
    FROM user_stage_times
)
SELECT
    prev_stage AS from_stage,
    event_type AS to_stage,
    ROUND(AVG(TIMESTAMPDIFF(HOUR, prev_stage_time, stage_time)), 1) AS avg_hours_between
FROM consecutive_stage_pairs
WHERE prev_stage IS NOT NULL
  AND stage_time >= prev_stage_time
  AND stage_order = prev_stage_order + 1
GROUP BY prev_stage, event_type
ORDER BY FIELD(event_type, 'signup', 'email_verified', 'kyc_submitted', 'kyc_approved',
               'bank_linked', 'first_deposit', 'plan_selected', 'subscribed');

-- Q4. Subscription conversion rate by acquisition channel
SELECT
    u.acquisition_channel,
    COUNT(DISTINCT u.user_id) AS total_users,
    COUNT(DISTINCT s.user_id) AS subscribed_users,
    ROUND(COUNT(DISTINCT s.user_id) / COUNT(DISTINCT u.user_id) * 100, 2) AS conversion_rate_pct
FROM users u
LEFT JOIN subscriptions s ON u.user_id = s.user_id
GROUP BY u.acquisition_channel
ORDER BY conversion_rate_pct DESC;

-- Q5. Subscription conversion rate by device type
SELECT
    u.device_type,
    COUNT(DISTINCT u.user_id) AS total_users,
    COUNT(DISTINCT s.user_id) AS subscribed_users,
    ROUND(COUNT(DISTINCT s.user_id) / COUNT(DISTINCT u.user_id) * 100, 2) AS conversion_rate_pct
FROM users u
LEFT JOIN subscriptions s ON u.user_id = s.user_id
GROUP BY u.device_type
ORDER BY conversion_rate_pct DESC;

-- Q6. Customer acquisition cost by paid acquisition channel
--     Campaign-attributed users only; organic/referral excluded.
WITH campaign_cost AS (
    SELECT channel, SUM(cost) AS total_cost
    FROM marketing_campaigns
    GROUP BY channel
),
campaign_conversions AS (
    SELECT
        c.channel,
        COUNT(DISTINCT s.user_id) AS subscribed_users
    FROM marketing_campaigns c
    JOIN users u ON u.marketing_campaign_id = c.campaign_id
    LEFT JOIN subscriptions s ON s.user_id = u.user_id
    GROUP BY c.channel
)
SELECT
    cv.channel,
    ct.total_cost,
    cv.subscribed_users,
    ROUND(ct.total_cost / NULLIF(cv.subscribed_users, 0), 2) AS cac
FROM campaign_conversions cv
JOIN campaign_cost ct ON cv.channel = ct.channel
ORDER BY cac;

-- Q7. Plan tier and MRR breakdown by acquisition channel
--     MRR remains populated on canceled rows, so current_mrr is
--     restricted to active subscriptions.
SELECT
    u.acquisition_channel,
    s.plan_tier,
    COUNT(DISTINCT s.user_id) AS subscriber_count,
    ROUND(AVG(s.mrr), 2) AS avg_mrr,
    ROUND(SUM(CASE WHEN s.status = 'active' THEN s.mrr ELSE 0 END), 2) AS current_mrr
FROM subscriptions s
JOIN users u ON s.user_id = u.user_id
GROUP BY u.acquisition_channel, s.plan_tier
ORDER BY u.acquisition_channel, FIELD(s.plan_tier, 'free', 'plus', 'premium');

-- Q8. Cancellation rate and cancellation reasons
SELECT
    status,
    COUNT(*) AS subscription_count,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM subscriptions) * 100, 2) AS pct_of_subscriptions
FROM subscriptions
GROUP BY status
ORDER BY subscription_count DESC;

SELECT
    cancellation_reason,
    COUNT(*) AS occurrences,
    ROUND(COUNT(*) / (SELECT COUNT(*) FROM subscriptions WHERE status = 'canceled') * 100, 2) AS pct_of_cancellations
FROM subscriptions
WHERE status = 'canceled'
GROUP BY cancellation_reason
ORDER BY occurrences DESC;

-- Q9. Cancellation rate by plan tier
SELECT
    plan_tier,
    COUNT(*) AS total_subscriptions,
    SUM(CASE WHEN status = 'canceled' THEN 1 ELSE 0 END) AS canceled_count,
    ROUND(SUM(CASE WHEN status = 'canceled' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS cancellation_rate_pct
FROM subscriptions
GROUP BY plan_tier
ORDER BY FIELD(plan_tier, 'free', 'plus', 'premium');