# RedFlag — Fraud Detection Engine in Pure SQL

A fraud analytics project simulating the day-to-day work of a fraud analyst at an Indian fintech.
Built entirely in MySQL no Python, no Excel, no ML against 200,000+ transactions from
**PayFast**, a fictional Indian payment aggregator handling UPI, card, netbanking, and wallet
payments across 20+ cities.

The mission: 12 fraud patterns are hidden in six months of transaction history. Find every one
of them using nothing but SQL.

## Patterns Detected

**Tier 1 — GROUP BY, HAVING, CASE WHEN**
1. Velocity fraud — 30+ transactions by one user in a single day
2. Round-amount clustering — 15+ suspiciously round-number transactions (money laundering)
3. Card testing — 30+ sub-₹10 transactions in a day (stolen card validation)
4. Failed-then-succeeded — repeated failed attempts followed by a matching success
5. Odd-hour concentration — 80%+ of activity between 2-4 AM (bot signature)

**Tier 2 — Joins, subqueries, EXISTS**
6. Mule accounts — large credits immediately cycled back out as debits
7. Refund abuse — refund rate above 40% (chargeback fraud)
8. Merchant collusion — top 5 customers driving 60%+ of a merchant's volume
9. Structuring — repeated transactions at ₹9,999, just under the KYC threshold
10. Dormant-then-active — 90+ day silence followed by a sudden burst (account takeover)

**Tier 3 — Window functions (LAG, ROW_NUMBER, CTEs)**
11. Velocity spike — a month's activity spiking to 5x+ a user's average
12. Geographic impossibility — the same user transacting in two cities within 60 minutes

## Results

| Pattern | Suspects Found |
|---|---|
| P1 Velocity Fraud | 50 |
| P2 Round-Amount Clustering | 25 |
| P3 Card Testing | 20 |
| P4 Failed-Then-Succeeded | 25 |
| P5 Odd-Hour Concentration | 20 |
| P6 Mule Accounts | 30 |
| P7 Refund Abuse | 24 |
| P8 Merchant Collusion | 15 merchants |
| P9 Structuring | 20 |
| P10 Dormant-Then-Active | 26 |
| P11 Velocity Spike | 66 |
| P12 Geographic Impossibility | 15 |

## Tech Stack

- **MySQL 8.0** (Workbench)
- GROUP BY / HAVING / CASE WHEN aggregation
- Correlated subqueries and EXISTS clauses
- Window functions: `LAG()`, `ROW_NUMBER() OVER (PARTITION BY ...)`
- CTEs (`WITH ... AS`) for multi-step analysis

## Why This Project

Fraud analytics is one of the fastest-growing analyst roles at Indian fintechs — Razorpay, Cred,
Slice, Jupiter, PhonePe all run teams doing exactly this: writing SQL to catch fraud patterns at
scale. This project is a hands-on simulation of that work, built as part of **The Unlox Academy**
Data Analytics track.
