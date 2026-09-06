# SaaS FinTech Product Funnel & Conversion Analysis

**By: Curtis Smail**

## Executive Summary

The product converts just 13.56% of signups into paying subscribers, with the largest loss occurring between plan selection and subscription. Using SQL, Python, and Power BI, I analyzed 8,000 signups, ~30,000 funnel events, and 1,085 subscriptions to identify where users drop off, which acquisition channels perform most efficiently, and where retention risk is concentrated.

The largest funnel loss occurs after plan selection: 35.3% of users who select a plan never complete subscription, followed by a separate bottleneck at KYC entry. Referral has the highest observed conversion rate at 42.3%, compared with 1.2% for Social, while Social and Affiliate have the highest CAC among the paid acquisition channels. Premium cancellations represent substantially greater cancelled-MRR exposure per customer than Plus cancellations.

These findings point to three priorities: investigate and reduce post-plan-selection friction, investigate KYC entry, and evaluate reallocating acquisition spend toward higher-performing channels while prioritizing retention by revenue exposure.

## Business Problem

The product has no data-driven view of where users drop out of the signup funnel, which acquisition channels are actually worth the spend behind them, or why subscribers cancel. Leadership needs to know where users are being lost, which channels deserve more or less investment, and where retention risk is concentrated — so product and marketing decisions can be based on evidence rather than instinct.

![Executive Overview](images/dashboard_executive_overview.png)

## Dashboard

Report structure: Executive Overview -> Funnel & Channel Detail -> Acquisition & Revenue -> Retention & Risk.

| Funnel & Channel Detail | Acquisition & Revenue | Retention & Risk |
|---|---|---|
| ![Funnel & Channel Detail](images/dashboard_funnel_channel_detail.png) | ![Acquisition & Revenue](images/dashboard_acquisition_revenue.png) | ![Retention & Risk](images/dashboard_retention_risk.png) |

## Methodology

1. **SQL** (MySQL): Built the schema, cleaned the data (casing standardization, deduplication, orphan handling), and ran an exploratory pass answering 10 business questions.
2. **Python**: Reproduced and asserted SQL data-quality checks, merged the tables into an analysis-ready dataframe, and went deeper with cohort analysis, chi-square and ANOVA testing, effect sizes, visualization, and statistical interpretation.
3. **Power BI**: Built a 4-page interactive dashboard using verified output tables so dashboard figures trace back to logic validated in SQL and Python.

## Tools & Technologies

**SQL:** JOINs, window functions, CASE, CTEs, aggregation, GROUP BY, anti-joins, schema design, data-quality checks, and query troubleshooting.

**Python:** pandas, merging, anti-joins, feature engineering, cohort analysis, Matplotlib/Seaborn, scipy.stats, chi-square, ANOVA, effect sizes, EDA, and statistical interpretation.

**Power BI:** DAX measures, data modelling and relationships, Power Query, conditional formatting, interactive filtering, and dashboard design.

## Key Findings

![Funnel & Channel Detail](images/dashboard_funnel_channel_detail.png)

1. **Largest funnel drop-off.** 35.3% of users who selected a plan never completed subscription — the largest loss point anywhere in the journey.
2. **KYC entry bottleneck.** `email_verified -> kyc_submitted` loses 29.4% of users, while `kyc_submitted -> kyc_approved` loses ~17.5%. The observed drop-off is concentrated at KYC entry rather than review.
3. **Referral performance.** Referral has the highest observed conversion rate at 42.3%, compared with 21.5% for Organic and single-digit rates for paid channels. The channel/conversion association is statistically significant (chi-square p < 0.001, Cramer's V = 0.347).
4. **Social and Affiliate efficiency.** Social and Affiliate have the lowest conversion rates (1.2% and 3.3%) and highest CAC ($619.86 and $785.14), making them candidates for spend review.
5. **Premium revenue risk.** Premium has fewer cancelled customers than Plus (38 vs. 59), but higher revenue exposure per cancellation ($22.03 vs. $8.99 on average).

**What the analysis did not find:** Device type showed no statistically significant relationship with conversion (chi-square p = 0.099). Time-to-convert also showed no significant difference across acquisition channels (ANOVA p = 0.75, eta-squared = 0.002). These results suggest channel is associated with whether users convert, but this analysis does not provide evidence that channel affects how quickly they convert.

**Note:** For this analysis, a user is considered subscribed only when a matching record exists in the `subscriptions` table. The funnel event log contained 21 subscription events without matching subscription records, so using the event log alone would have overstated conversion. All conversion figures in this README, the SQL queries, and the notebook use this subscriptions-table definition unless otherwise noted.

## Key Metrics

| # | Metric | Value |
|---|---|---|
| 1 | Overall conversion rate | 13.56% |
| 2 | Largest funnel drop-off (Plan Selected -> Subscribed) | 35.30% |
| 3 | Highest vs. lowest channel conversion | Referral 42.3% \| Social 1.2% |
| 4 | Lowest vs. highest paid CAC | Paid Search $403.73 \| Affiliate $785.14 |
| 5 | Cancelled MRR per Customer: Premium vs. Plus | $22.03 \| $8.99 |
| 6 | Top cancellation reason | Technical Issues (21.9%) |

*Full breakdown of all 10 SQL business questions available in the [queries](sql/exploratory_queries.sql); full statistical detail in the [notebook](notebooks/funnel_analysis.ipynb).*

## Recommendations

1. **Investigate and reduce post-plan-selection drop-off** — Use a controlled A/B test to determine whether checkout or confirmation changes improve completion.
2. **Investigate KYC entry friction** — Treat KYC entry separately from KYC review, since the largest KYC-related loss occurs before submission, not during it.
3. **Review paid acquisition allocation** — Reduce or test reallocating spend away from Social and Affiliate toward better-performing channels, but validate decisions with ROI/payback analysis rather than CAC alone.
4. **Address technical-issue cancellations** — Technical Issues are the largest cancellation reason at 21.9% and represent a directly addressable product/engineering opportunity.
5. **Prioritize retention by revenue exposure** — Weight retention efforts by financial impact rather than customer count alone, with Premium cancellations receiving higher priority.

## Next Steps

1. **Build a churn-risk model for active subscribers** using plan tier, acquisition channel, and engagement signals, benchmarked against the plan-tier revenue-exposure heuristic used here.
2. **A/B test a simplified subscription flow** to determine whether post-plan-selection friction is a causal driver of the largest funnel loss.
3. **Estimate acquisition ROI** by combining CAC with time-to-convert and plan-tier mix to estimate channel payback periods, not just upfront acquisition cost.
4. **Connect the Power BI dashboard to a live data source** for production-style monitoring instead of static CSV exports.

## Data & Data Quality Notes

The dataset used in this project is synthetically generated to simulate a real-world FinTech signup funnel and subscription product. The events, timestamps, and subscription records are artificial, but the dataset was engineered to mirror realistic user behaviour, funnel drop-off patterns, and common data-quality issues such as duplicate events, orphaned records, casing inconsistencies, and phantom subscriptions. This project serves as a proof of concept to demonstrate end-to-end data cleaning, funnel/cohort analysis, and dashboard development without exposing proprietary product or customer data. See `sql/schema_and_load.sql` for a full breakdown of known data quality issues and how each was handled.

## How to Run

1. Clone this repository and install dependencies: `pip install -r requirements.txt`
2. Cleaned data is available directly in `data/cleaned/` — no database setup required to run the notebook
3. Open `notebooks/funnel_analysis.ipynb` and run all cells
4. To explore the SQL work, import the CSVs in `data/cleaned/` into MySQL and run `sql/schema_and_load.sql` followed by `sql/exploratory_queries.sql`
5. To explore the dashboard, open `power_bi/Funnel_Analysis.pbix` in Power BI Desktop
