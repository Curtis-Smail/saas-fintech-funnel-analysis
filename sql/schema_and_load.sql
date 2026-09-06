-- Database setup
 
DROP DATABASE IF EXISTS saas_funnel;
CREATE DATABASE saas_funnel;
USE saas_funnel;
 
-- Table creation
 
CREATE TABLE marketing_campaigns (
    campaign_id     INT PRIMARY KEY,
    campaign_name   VARCHAR(100) NOT NULL,
    channel         VARCHAR(30)  NOT NULL,
    cost            DECIMAL(10,2) NOT NULL,
    start_date      DATE NOT NULL,
    end_date        DATE NOT NULL
);
 
CREATE TABLE users (
    user_id                 INT PRIMARY KEY,
    signup_date             DATE NOT NULL,
    acquisition_channel     VARCHAR(30) NOT NULL,
    device_type             VARCHAR(20) NOT NULL,
    country                 VARCHAR(50) NOT NULL,
    age                     TINYINT UNSIGNED NOT NULL,
    occupation              VARCHAR(50) NOT NULL,
    referral_source         VARCHAR(50) NULL,      -- NULL unless acquisition_channel = 'referral'
    marketing_campaign_id   INT NULL               -- NULL for organic/referral users with no campaign
);
 
CREATE TABLE funnel_events (
    event_id            INT PRIMARY KEY,
    user_id             INT NOT NULL,
    event_type          VARCHAR(30) NOT NULL,
    event_timestamp     DATETIME(6) NOT NULL,
    platform            VARCHAR(10) NOT NULL
);
 
CREATE TABLE subscriptions (
    subscription_id       INT PRIMARY KEY,
    user_id                INT NOT NULL,
    plan_tier              VARCHAR(20) NOT NULL,
    mrr                    DECIMAL(6,2) NOT NULL,
    start_date             DATE NOT NULL,
    end_date               DATE NULL,        -- NULL while subscription is active
    status                 VARCHAR(20) NOT NULL,
    cancellation_reason    VARCHAR(50) NULL, -- NULL unless status = 'canceled'
    payment_method         VARCHAR(20) NULL  -- NULL for $0 (free tier) subscriptions
);
 
-- Load raw CSVs
-- Replace <username> below with your local Windows username, or point
-- these paths at wherever csv_raw/ lives on your machine
 
LOAD DATA LOCAL INFILE 'C:/Users/<username>/OneDrive/Desktop/SaaS_Funnel/csv_raw/marketing_campaigns.csv'
INTO TABLE marketing_campaigns
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;
 
LOAD DATA LOCAL INFILE 'C:/Users/<username>/OneDrive/Desktop/SaaS_Funnel/csv_raw/users.csv'
INTO TABLE users
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(user_id, signup_date, acquisition_channel, device_type, country, age,
 occupation, @referral_source, @marketing_campaign_id)
SET
    referral_source = NULLIF(@referral_source, ''),
    marketing_campaign_id = NULLIF(@marketing_campaign_id, '');
 
LOAD DATA LOCAL INFILE 'C:/Users/<username>/OneDrive/Desktop/SaaS_Funnel/csv_raw/funnel_events.csv'
INTO TABLE funnel_events
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS;
 
-- IGNORE deliberate: 3 rows share a duplicate subscription_id (known
-- data-quality issue); skips them with a warning instead of aborting the load. 
LOAD DATA LOCAL INFILE 'C:/Users/<username>/OneDrive/Desktop/SaaS_Funnel/csv_raw/subscriptions.csv'
IGNORE INTO TABLE subscriptions
FIELDS TERMINATED BY ',' OPTIONALLY ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(subscription_id, user_id, plan_tier, mrr, start_date, @end_date, status,
 @cancellation_reason, @payment_method)
SET
    end_date = NULLIF(@end_date, ''),
    cancellation_reason = NULLIF(@cancellation_reason, ''),
    payment_method = NULLIF(@payment_method, '');
 
-- Validate NULL and empty-string handling
SELECT
    SUM(referral_source IS NULL) AS referral_source_null,
    SUM(referral_source = '') AS referral_source_empty,
    SUM(marketing_campaign_id IS NULL) AS campaign_id_null
FROM users;
 
SELECT
    SUM(end_date IS NULL) AS end_date_null,
    SUM(cancellation_reason IS NULL) AS reason_null,
    SUM(cancellation_reason = '') AS reason_empty,
    SUM(payment_method IS NULL) AS payment_null,
    SUM(payment_method = '') AS payment_empty
FROM subscriptions;
 
-- Row counts
 
SELECT 'marketing_campaigns' AS table_name, COUNT(*) AS row_count FROM marketing_campaigns
UNION ALL
SELECT 'users', COUNT(*) FROM users
UNION ALL
SELECT 'funnel_events', COUNT(*) FROM funnel_events
UNION ALL
SELECT 'subscriptions', COUNT(*) FROM subscriptions;
 
-- Format standardization
 
SELECT DISTINCT event_type FROM funnel_events ORDER BY event_type;
 
UPDATE funnel_events
SET event_type = LOWER(REPLACE(event_type, ' ', '_'));
 
UPDATE funnel_events
SET event_type = CASE event_type
    WHEN 'kycapproved'    THEN 'kyc_approved'
    WHEN 'kycsubmitted'   THEN 'kyc_submitted'
    WHEN 'banklinked'     THEN 'bank_linked'
    WHEN 'firstdeposit'   THEN 'first_deposit'
    WHEN 'emailverified'  THEN 'email_verified'
    WHEN 'planselected'   THEN 'plan_selected'
    ELSE event_type
END;
 
SELECT DISTINCT event_type FROM funnel_events ORDER BY event_type;
 
-- Everything is now formatted as intended, ready to further explore
 
-- Orphaned funnel_events: user_id not present in users
-- Kept as-is, excluded via JOIN rather than deleted
SELECT COUNT(*) AS orphaned_event_rows
FROM funnel_events fe
LEFT JOIN users u ON fe.user_id = u.user_id
WHERE u.user_id IS NULL;
 
-- Identify duplicate event logs based on user, event type,
-- timestamp, and platform
SELECT user_id, event_type, event_timestamp, platform, COUNT(*) AS n
FROM funnel_events
GROUP BY user_id, event_type, event_timestamp, platform
HAVING COUNT(*) > 1;
 
-- Remove duplicate event logs using ROW_NUMBER(),
-- retaining the lowest event_id for each duplicate group
DELETE FROM funnel_events
WHERE event_id IN (
    SELECT event_id FROM (
        SELECT
            event_id,
            ROW_NUMBER() OVER (
                PARTITION BY user_id, event_type, event_timestamp, platform
                ORDER BY event_id
            ) AS rn
        FROM funnel_events
    ) ranked
    WHERE rn > 1
);
 
-- Confirm the dedup worked: should return 0 rows
SELECT user_id, event_type, event_timestamp, platform, COUNT(*) AS n
FROM funnel_events
GROUP BY user_id, event_type, event_timestamp, platform
HAVING COUNT(*) > 1;
 
-- Identify events occurring before signup_date
-- Retain for data-quality review; exclude from time-based analysis
-- Flagged, not deleted — excluded only from time-based analysis
SELECT fe.event_id, fe.user_id, fe.event_type, fe.event_timestamp, u.signup_date
FROM funnel_events fe
JOIN users u ON fe.user_id = u.user_id
WHERE fe.event_timestamp < u.signup_date;
 
-- Identify subscribed events without a recorded signup event
-- Retain records; exclude from funnel-stage analysis
SELECT DISTINCT fe.user_id
FROM funnel_events fe
WHERE fe.event_type = 'subscribed'
  AND NOT EXISTS (
      SELECT 1
      FROM funnel_events signup
      WHERE signup.user_id = fe.user_id
        AND signup.event_type = 'signup'
  );
 
-- Repeat events per user/type — inspected, not auto-removed since
-- retries are meaningful funnel behaviour
SELECT user_id, event_type, COUNT(*) AS occurrences
FROM funnel_events
GROUP BY user_id, event_type
HAVING COUNT(*) > 1
ORDER BY occurrences DESC;
 
-- cancellation_reason populated on a non-canceled row
SELECT *
FROM subscriptions
WHERE status <> 'canceled' AND cancellation_reason IS NOT NULL;
 
-- Null out: shouldn't carry a cancellation reason unless canceled
UPDATE subscriptions
SET cancellation_reason = NULL
WHERE status <> 'canceled' AND cancellation_reason IS NOT NULL;
 
-- Check for invalid campaign references
-- Relationship is validated but not enforced by a foreign key
SELECT COUNT(*) AS bad_campaign_refs
FROM users u
LEFT JOIN marketing_campaigns c ON u.marketing_campaign_id = c.campaign_id
WHERE u.marketing_campaign_id IS NOT NULL AND c.campaign_id IS NULL;
 
-- Null checks — confirm nulls only appear where expected
SELECT
    SUM(user_id IS NULL) AS null_user_id,
    SUM(signup_date IS NULL) AS null_signup_date,
    SUM(acquisition_channel IS NULL) AS null_channel
FROM users;
 
SELECT
    SUM(event_id IS NULL) AS null_event_id,
    SUM(user_id IS NULL) AS null_user_id,
    SUM(event_type IS NULL) AS null_event_type,
    SUM(event_timestamp IS NULL) AS null_timestamp
FROM funnel_events;
 
-- Final row counts post-cleaning (compare to baseline above)
SELECT 'marketing_campaigns' AS table_name, COUNT(*) AS row_count FROM marketing_campaigns
UNION ALL
SELECT 'users', COUNT(*) FROM users
UNION ALL
SELECT 'funnel_events', COUNT(*) FROM funnel_events
UNION ALL
SELECT 'subscriptions', COUNT(*) FROM subscriptions;

-- Indexes to support exploratory_queries.sql
CREATE INDEX idx_funnel_user ON funnel_events(user_id);
CREATE INDEX idx_funnel_event_type ON funnel_events(event_type);
CREATE INDEX idx_users_channel ON users(acquisition_channel);