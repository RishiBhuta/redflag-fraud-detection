-- =====================================================================
-- RedFlag — Fraud Detection Submission
-- Student: Rishi Bhuta | Batch: DA-DS-1
-- =====================================================================
USE redflag;

-- =====================================================================
-- PATTERN 1 · VELOCITY FRAUD
-- What I'm looking for: a single user with 30+ transactions on one
-- calendar day. Real users top out at 3-8 transactions/day even on
-- busy days; 30+ in a day means a script, an automated account
-- takeover, or a merchant running a churning scheme.
-- Expected suspects: ~45-55 user-days
-- =====================================================================
SELECT
    user_id,
    DATE(txn_time) AS attack_date,
    COUNT(*)        AS daily_txn_count
FROM transactions
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY daily_txn_count DESC;
-- My findings: 50 suspect user-days flagged (within the expected 45-55).
-- Top offenders: user 14556 with 60 txns on 2024-05-28, user 14569 with
-- 60 txns on 2024-04-03, user 14564 with 59 txns on 2024-02-15.

-- =====================================================================
-- PATTERN 2 · ROUND-AMOUNT CLUSTERING
-- What I'm looking for: users with 15+ transactions at exactly a round
-- rupee amount (100/200/500/1000/2000/5000/10000). Genuine e-commerce
-- and food-delivery charges almost never land on a clean round number
-- once tax, delivery fee, and discounts are applied, so heavy clustering
-- on round figures is a classic money-laundering signature.
-- Expected suspects: exactly 25
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS round_amount_txn_count
FROM transactions
WHERE amount IN (100, 200, 500, 1000, 2000, 5000, 10000)
GROUP BY user_id
HAVING COUNT(*) >= 15
ORDER BY round_amount_txn_count DESC;
-- My findings: exactly 25 suspects flagged, matching the seeded count.
-- Examples: users 14533, 14534, and 14535 each hit 30 round-amount txns.

-- =====================================================================
-- PATTERN 3 · CARD TESTING
-- What I'm looking for: a user with 30+ transactions under Rs 10 on a
-- single day. Fraudsters test stolen card dumps with tiny purchases to
-- see which cards are still live before running a bigger charge.
-- Expected suspects: exactly 20
-- =====================================================================
SELECT
    user_id,
    DATE(txn_time) AS test_date,
    COUNT(*)        AS micro_txn_count
FROM transactions
WHERE amount < 10
GROUP BY user_id, DATE(txn_time)
HAVING COUNT(*) >= 30
ORDER BY micro_txn_count DESC;
-- My findings: exactly 20 suspects flagged, matching the seeded count.

-- =====================================================================
-- PATTERN 4 · FAILED-THEN-SUCCEEDED
-- What I'm looking for: card-testing behaviour, but the specific
-- signature here is a high volume of FAILED transactions (simplified),
-- or FAILED transactions each followed within 2 minutes by a SUCCESS
-- of the same amount (advanced) — a fraudster retrying a stolen card
-- until one combination clears.
-- Expected suspects: exactly 25
-- =====================================================================

-- Simplified (Week 3): 20+ failed transactions for a single user
SELECT
    user_id,
    COUNT(*) AS failed_txn_count
FROM transactions
WHERE status = 'FAILED'
GROUP BY user_id
HAVING COUNT(*) >= 20
ORDER BY failed_txn_count DESC;

-- Advanced (Week 4): 20+ FAILED->SUCCESS pairs, same amount, within 2 min
SELECT
    f.user_id,
    COUNT(*) AS retry_success_pairs
FROM transactions f
JOIN transactions s
    ON  s.user_id   = f.user_id
    AND s.amount    = f.amount
    AND s.txn_time  > f.txn_time
    AND TIMESTAMPDIFF(MINUTE, f.txn_time, s.txn_time) <= 2
WHERE f.status = 'FAILED'
  AND s.status = 'SUCCESS'
GROUP BY f.user_id
HAVING COUNT(*) >= 20
ORDER BY retry_success_pairs DESC;
-- My findings: both versions independently flag exactly 25 suspects,
-- matching the seeded count and confirming the same fraudster set.

-- =====================================================================
-- PATTERN 5 · ODD-HOUR CONCENTRATION
-- What I'm looking for: a user with 30+ total transactions where 80%+
-- of them happen between 2 AM and 4 AM IST — outside normal Indian
-- waking hours but squarely within US/Eastern-Europe business hours,
-- a common bot-script signature.
-- Expected suspects: exactly 20
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS total_txns,
    SUM(CASE WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1 ELSE 0 END) AS odd_hour_txns,
    ROUND(SUM(CASE WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1 ELSE 0 END) / COUNT(*) * 100, 1) AS odd_hour_pct
FROM transactions
GROUP BY user_id
HAVING total_txns >= 30
   AND SUM(CASE WHEN HOUR(txn_time) BETWEEN 2 AND 4 THEN 1 ELSE 0 END) / COUNT(*) >= 0.8
ORDER BY odd_hour_pct DESC;
-- My findings: exactly 20 suspects flagged, matching the seeded count.

-- =====================================================================
-- PATTERN 6 · MULE ACCOUNTS
-- What I'm looking for: accounts that receive a large CREDIT and pass
-- most of it straight back out as a DEBIT shortly after — the human
-- ATMs that fraud rings use to move stolen funds through the system.
-- Expected suspects: exactly 30
-- =====================================================================

-- Simplified (Week 3): 8+ CREDIT transactions
SELECT
    user_id,
    COUNT(*) AS credit_txn_count
FROM transactions
WHERE txn_type = 'CREDIT'
GROUP BY user_id
HAVING COUNT(*) >= 8
ORDER BY credit_txn_count DESC;

-- Advanced (Week 4): 5+ CREDIT->DEBIT pairs, DEBIT >= 70% of CREDIT,
-- within 30 minutes, using a correlated EXISTS subquery
SELECT
    c.user_id,
    COUNT(*) AS mule_event_count
FROM transactions c
WHERE c.txn_type = 'CREDIT'
  AND EXISTS (
        SELECT 1
        FROM transactions d
        WHERE d.user_id   = c.user_id
          AND d.txn_type  = 'DEBIT'
          AND d.txn_time  > c.txn_time
          AND TIMESTAMPDIFF(MINUTE, c.txn_time, d.txn_time) <= 30
          AND d.amount   >= 0.7 * c.amount
  )
GROUP BY c.user_id
HAVING COUNT(*) >= 5
ORDER BY mule_event_count DESC;
-- My findings: both versions flag exactly 30 suspects, matching the
-- seeded count and confirming the same account set.

-- =====================================================================
-- PATTERN 7 · REFUND ABUSE
-- What I'm looking for: a user with 20+ total transactions where more
-- than 40% are refunds. Genuine users sit well under a 5% refund rate;
-- anything above 40% points to chargeback fraud or a merchant loophole
-- being exploited repeatedly.
-- Expected suspects: ~24-25
-- =====================================================================
SELECT
    user_id,
    total_txns,
    refund_txns,
    ROUND(refund_txns / total_txns * 100, 1) AS refund_pct
FROM (
    SELECT
        user_id,
        COUNT(*) AS total_txns,
        SUM(CASE WHEN txn_type = 'REFUND' THEN 1 ELSE 0 END) AS refund_txns
    FROM transactions
    GROUP BY user_id
) AS user_refund_stats
WHERE total_txns >= 20
  AND refund_txns / total_txns > 0.4
ORDER BY refund_pct DESC;
-- My findings: 24 suspects flagged (within the expected 24-25).
-- Worst offender: user 14662 with a 64.1% refund rate over 39 txns.

-- =====================================================================
-- PATTERN 8 · MERCHANT COLLUSION
-- What I'm looking for: a merchant whose top 5 customers by rupee
-- volume account for more than 60% of the merchant's total business.
-- Legitimate retail merchants have long customer tails; a merchant
-- concentrated on a handful of users is either a tiny B2B operation or
-- is colluding with those users to launder money through fake sales.
-- Expected suspects: exactly 15 merchants
-- =====================================================================
WITH merchant_user_totals AS (
    SELECT merchant_id, user_id, SUM(amount) AS user_volume
    FROM transactions
    GROUP BY merchant_id, user_id
),
ranked_users AS (
    SELECT
        merchant_id,
        user_id,
        user_volume,
        ROW_NUMBER() OVER (PARTITION BY merchant_id ORDER BY user_volume DESC) AS rn
    FROM merchant_user_totals
),
merchant_totals AS (
    SELECT merchant_id, SUM(amount) AS total_volume
    FROM transactions
    GROUP BY merchant_id
),
top5_volume AS (
    SELECT merchant_id, SUM(user_volume) AS top5_volume
    FROM ranked_users
    WHERE rn <= 5
    GROUP BY merchant_id
)
SELECT
    t5.merchant_id,
    mt.total_volume,
    t5.top5_volume,
    ROUND(t5.top5_volume / mt.total_volume * 100, 1) AS top5_pct
FROM top5_volume t5
JOIN merchant_totals mt ON mt.merchant_id = t5.merchant_id
WHERE t5.top5_volume / mt.total_volume > 0.6
ORDER BY top5_pct DESC;
-- My findings: exactly 15 merchants flagged, matching the seeded count.
-- Several (e.g. merchant 8, 12, 13) have 99%+ of volume from just 5 users.

-- =====================================================================
-- PATTERN 9 · JUST-UNDER-THRESHOLD (STRUCTURING)
-- What I'm looking for: a user with 10+ transactions at exactly
-- Rs 9,999 — deliberately staying one rupee under the Rs 10,000 KYC
-- reporting threshold. Classic structuring/smurfing, illegal on its own
-- even without any other fraud attached.
-- Expected suspects: exactly 20
-- =====================================================================
SELECT
    user_id,
    COUNT(*) AS structured_txn_count
FROM transactions
WHERE amount = 9999.00
GROUP BY user_id
HAVING COUNT(*) >= 10
ORDER BY structured_txn_count DESC;
-- My findings: exactly 20 suspects flagged, matching the seeded count.

-- =====================================================================
-- PATTERN 10 · DORMANT-THEN-ACTIVE
-- What I'm looking for: a user with a 90+ day gap between two
-- consecutive transactions, followed by 15+ transactions after that
-- gap. This is the signature of account takeover — a fraudster
-- monetising a dormant account before the real owner notices.
-- Expected suspects: ~25-27
-- =====================================================================
WITH gaps AS (
    SELECT
        user_id,
        txn_time,
        LAG(txn_time) OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_txn_time
    FROM transactions
),
reactivations AS (
    SELECT user_id, txn_time AS reactivation_time
    FROM gaps
    WHERE TIMESTAMPDIFF(DAY, prev_txn_time, txn_time) >= 90
)
SELECT
    r.user_id,
    r.reactivation_time,
    COUNT(t.txn_id) AS post_gap_txn_count
FROM reactivations r
JOIN transactions t
    ON t.user_id = r.user_id
   AND t.txn_time >= r.reactivation_time
GROUP BY r.user_id, r.reactivation_time
HAVING COUNT(t.txn_id) >= 15
ORDER BY post_gap_txn_count DESC;
-- My findings: 26 suspects flagged (within the expected 25-27).

-- =====================================================================
-- PATTERN 11 · VELOCITY SPIKE
-- What I'm looking for: a user whose busiest month (peak) is at least
-- 5x their average monthly transaction count across the full 6-month
-- window, with the peak month itself at least 20 transactions. This is
-- the ML-free version of anomaly detection — a sudden, sustained change
-- in behaviour almost always means account takeover.
-- Expected suspects: ~35-45
-- =====================================================================
WITH monthly_counts AS (
    SELECT
        user_id,
        DATE_FORMAT(txn_time, '%Y-%m') AS txn_month,
        COUNT(*) AS month_txn_count
    FROM transactions
    GROUP BY user_id, DATE_FORMAT(txn_time, '%Y-%m')
),
user_stats AS (
    SELECT
        user_id,
        SUM(month_txn_count) / 6 AS avg_monthly_count,  -- averaged over the fixed 6-month window
        MAX(month_txn_count)     AS peak_month_count
    FROM monthly_counts
    GROUP BY user_id
)
SELECT
    user_id,
    ROUND(avg_monthly_count, 2) AS avg_monthly_count,
    peak_month_count,
    ROUND(peak_month_count / avg_monthly_count, 2) AS spike_ratio
FROM user_stats
WHERE peak_month_count >= 20
  AND peak_month_count >= 5 * avg_monthly_count
ORDER BY spike_ratio DESC;
-- My findings: 66 suspects flagged — above the brief's 35-45 estimate,
-- but the pattern itself is correct: a clean core of 20 users transact
-- in exactly ONE month (spike_ratio = 6.00 for all of them, e.g. users
-- 14556, 14559, 14564, 14569), which is the seeded account-takeover
-- cohort. The rest are lower-conviction cases (spike_ratio just above
-- 5) that the brief itself describes as expected "noise" from genuine
-- low-baseline users having one busy month; my dataset instance simply
-- produced more of them than the brief's estimate.

-- =====================================================================
-- PATTERN 12 · GEOGRAPHIC IMPOSSIBILITY
-- What I'm looking for: the same user transacting in two different
-- cities within 60 minutes — physically impossible for one person,
-- and a strong signal of account takeover or a stolen card being used
-- simultaneously by a fraud syndicate in different locations.
-- Expected suspects: exactly 15
-- =====================================================================
WITH ordered_txns AS (
    SELECT
        user_id,
        city,
        txn_time,
        LAG(city)     OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_city,
        LAG(txn_time) OVER (PARTITION BY user_id ORDER BY txn_time) AS prev_txn_time
    FROM transactions
)
SELECT DISTINCT
    user_id
FROM ordered_txns
WHERE prev_city IS NOT NULL
  AND city <> prev_city
  AND TIMESTAMPDIFF(MINUTE, prev_txn_time, txn_time) <= 60
ORDER BY user_id;
-- My findings: exactly 15 suspects flagged, matching the seeded count.
-- Example: user 14741 jumped from Vadodara to Thiruvananthapuram in
-- just 30 minutes on 2024-03-13.
