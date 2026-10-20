# Marketing Data Platform

A unified, tested and documented data product for **Facebook Ads** and **Snapchat Ads** performance, built with **Databricks (Unity Catalog)**, **dbt**, **Elementary** and **GitHub Actions**.

Marketers no longer need to open each ad platform and merge numbers by hand. One governed table, `fct_marketing_spend`, answers spend, impressions, clicks, CTR, CPC and CPM across both platforms, and is ready for SQL, BI tools and AI assistants.

## Contents

1. [Quick answers](#1-quick-answers)
2. [Business problem and goal](#2-business-problem-and-goal)
3. [Architecture](#3-architecture)
4. [The source data and what profiling revealed](#4-the-source-data-and-what-profiling-revealed)
5. [Design decisions and why](#5-design-decisions-and-why)
6. [Data model](#6-data-model)
7. [Data quality](#7-data-quality)
8. [Observability with Elementary](#8-observability-with-elementary)
9. [Environments](#9-environments)
10. [Security and Unity Catalog permissions](#10-security-and-unity-catalog-permissions)
11. [CI/CD](#11-cicd)
12. [Results: the business questions answered](#12-results-the-business-questions-answered)
13. [How to run it](#13-how-to-run-it)
14. [Repository structure](#14-repository-structure)
15. [Known limitations and assumptions](#15-known-limitations-and-assumptions)
16. [Future work](#16-future-work)

---

## 1. Quick answers

| Question | Answer |
|---|---|
| Total advertising spend | **8,439,506.41 EUR** |
| Spend on Facebook | **8,408,976.87 EUR** (2025) |
| Spend on Snapchat | **30,529.54 EUR** (2024) |
| Impressions: Facebook / Snapchat | 905,449,421 / 33,395,784 |
| Clicks: Facebook / Snapchat | 5,737,710 / 19,012 |
| Which platform generated more clicks? | Facebook, by a wide margin |
| CTR: Facebook / Snapchat | 0.634% / 0.057% |
| CPC: Facebook / Snapchat | 1.47 EUR / 1.61 EUR |
| CPM: Facebook / Snapchat | 9.29 EUR / 0.91 EUR |
| Campaign with the most clicks | `usa_ios_display_ggl_awareness_20230916_interest-stack-v3_video-views` (1,389,414 clicks) |

All amounts are in euros (`spend_eur`). See [section 12](#12-results-the-business-questions-answered) for the full results and the caveats that go with them, especially that the two platforms cover different years.

---

## 2. Business problem and goal

The Marketing team runs paid campaigns on Facebook and Snapchat. Before this project:

| Problem | How this project addresses it |
|---|---|
| Marketers manually visit each platform and combine data in Excel | One table with both platforms in the same shape |
| No unified view, because each platform structures data differently | Staging models normalise names, types and keys per platform |
| Data is hard for other teams to reach | Final tables are readable by everyone in the account through Unity Catalog |
| Other teams cannot reuse the data | A documented dimensional model (facts and a dimension) built for reuse |
| No governance, documentation, lineage or monitoring | dbt docs and lineage, automated tests, Elementary observability, permissions in Unity Catalog |

**Goal:** treat this as the first version of a real internal Marketing Data Platform, balancing usability, modelling quality, data quality, security, maintainability and scalability.

---

## 3. Architecture

```
 Facebook Ads CSVs (5)        Snapchat Ads CSVs (4)
          \                          /
           v                        v
        +-------------------------------+
        | Databricks bronze (raw)       |   bronze_production.cdc_staging
        +---------------+---------------+
                        v
        +-------------------------------+
        | dbt staging        (views)    |   rename, cast, clean. One model per source table
        +---------------+---------------+
                        v
        +-------------------------------+
        | dbt intermediate   (tables)   |   attach campaign/ad group/account, unify platforms
        +---------------+---------------+
                        v
        +-------------------------------+
        | dbt marts          (tables)   |   dim_marketing_campaigns
        |                               |   fct_marketing_ad_performance_daily  (incremental)
        |                               |   fct_marketing_spend
        +-------+-------+-------+-------+
                |       |       |
            Analysts   BI tools  AI assistants
```

| Layer | Catalog (production) | Purpose |
|---|---|---|
| Raw (bronze) | `bronze_production` | Untouched exports. Replayable source of truth |
| Staging, intermediate (silver) | `silver_production` | Transformation logic |
| Marts (gold) | `gold_production` | The consumption layer. The only catalog regular users can read |

The layers are separated by catalog, schema and permission, so raw data, transformation logic, analytical models and the consumption layer can each be governed independently.

---

## 4. The source data and what profiling revealed

Nine CSV files were provided: five for Facebook (stats, accounts, campaigns, ad groups, ads) and four for Snapchat (stats, ads, ad groups, campaigns). Before designing anything, each file was profiled. Every design choice below traces back to one of these findings.

| Finding | Evidence | Consequence |
|---|---|---|
| Missing values are the **literal text `null`**, not blank cells | 24,337 Facebook click values, 1,474 Facebook impression values, 111 Snapchat click values | Databricks may store those columns as text. Staging uses `try_cast`, which converts `null` text to a real NULL instead of failing |
| Facebook spend is in **two currencies** | 14 EUR accounts and 2 USD accounts. USD accounts hold 72.8% of the raw Facebook spend figure | Raw spend cannot be summed. A currency conversion is required |
| Snapchat rows are **per ad, per day, per country** | 1,757 duplicate (ad, date) pairs, but zero duplicates once country is included (DE, CH, AT, US) | The grain must include country. Deduplicating on (ad, date) would silently omi and delete real data |
| Snapchat ad groups are a **history table** | 267 rows for 264 distinct ad groups. The 3 repeated ad groups are used by ads with stats | Joining without keeping the latest version inflates Snapchat to 4,464 rows and 44,519.38 EUR (instead of 2,809 rows and 30,529.54 EUR, a 46% overstatement) |
| 304 Snapchat ads reference **ad groups missing** from the export | Orphans exist in the ad table. None of them has stats | No numbers are affected, so the check warns instead of failing |
| The platforms **never overlap in time** | Facebook: 2025-01-01 to 2025-12-31. Snapchat: 2024-01-01 to 2024-12-02 | Compare totals and rates, not month against month |
| Facebook IDs have up to **18 digits** | Larger than a double can represent exactly | IDs must be stored as text or bigint. They are cast to string |
| Column names already match across platforms | `ad_spend`, `ad_impressions`, `ad_clicks`, `ad_date` are used by both | The real differences are ID types, join paths and where currency lives, not column names |
| Zero-valued metrics are common | 312 campaign-days with zero clicks, 311 with zero impressions | Ratios must handle division by zero safely |

---

## 5. Design decisions and why

### 5.1 Grain and model structure

**Decision:** two fact tables and one dimension.

| Model | One row represents | Why |
|---|---|---|
| `fct_marketing_ad_performance_daily` | one **platform, ad, day, country** | The finest grain that exists in the data. Nothing is lost and every measure is additive |
| `fct_marketing_spend` | one **platform, campaign, day, currency** | What marketers actually ask about. Matches the grain suggested in the brief. Built from the ad-level fact, so the two can never disagree |
| `dim_marketing_campaigns` | one **platform, campaign** | Keeps descriptive text (names) out of the fact tables |

**Alternative rejected:** a single campaign-level table. It would have been simpler but would discard the ad and country detail, which could never be recovered later.

### 5.2 Keys

No single source column is unique, so the facts use **surrogate keys** generated with `dbt_utils.generate_surrogate_key` from the grain columns:

- `ad_performance_key` = platform + ad_id + ad_date + country_code
- `campaign_day_key` = platform + campaign_id + ad_date + currency_code
- `campaign_key` = platform + campaign_id (joins facts to the dimension)

Every key is tested for uniqueness and non-null. `campaign_key` includes the platform because the same numeric ID could exist on both platforms.

### 5.3 Platform normalisation

| Concept | Facebook | Snapchat | Unified column |
|---|---|---|---|
| Platform | constant | constant | `platform` (`facebook` / `snapchat`) |
| Ad ID | `ad_id` (bigint) | `ad_detail_id` (UUID) | `ad_id` (string) |
| Date | `ad_date` | `ad_date` | `ad_date` (date) |
| Country | not provided | `ad_country` | `country_code` (NULL for Facebook) |
| Currency | from the account table | on each stats row | `currency_code` |
| Campaign hierarchy | ads link directly to ad group, campaign, account | ad to ad group (versioned) to campaign to account | `campaign_id`, `campaign_name`, `account_id` |

All IDs are cast to string so both platforms share one column type. Both intermediate "details" models resolve their platform's hierarchy, and `int_marketing_ads_daily` stacks both with `union all` into one identical column set.

### 5.4 Null handling

| Column | Rule | Reason |
|---|---|---|
| spend, impressions, clicks (staging) | `try_cast`: the text `null` becomes a real NULL | Raw data contains the word `null`. A plain cast would crash |
| impressions (fact) | NULL becomes 0 | Every missing-impressions row has zero spend, so 0 is accurate |
| clicks (fact) | NULL becomes 0, and `is_clicks_imputed` is set to TRUE | Facebook has 24,337 missing and only 42 explicit zero clicks, which strongly suggests "missing" means "zero". It is an inference, so every affected row is flagged |
| CTR, CPC, CPM | divide with `nullif(denominator, 0)` | A zero denominator gives NULL ("not defined") instead of an error or a misleading 0. A fake CPC of 0 would read as free clicks |

### 5.5 Currency

73% of the raw Facebook spend figure sits in USD accounts, so adding raw spend would mix euros and dollars. The model keeps `spend` in the account's own currency and adds `spend_eur`, converted through the `fx_rates_to_eur` seed (1 EUR = 1.1750 USD, the ECB reference rate on 31 December 2025). The headline column is named `spend_eur` so humans and AI assistants cannot mistake it for native currency. See the [limitations](#15-known-limitations-and-assumptions) for what this simplification costs.

### 5.6 Deduplication

Two different problems, two different fixes:

- **Snapchat ad group versions:** `qualify row_number() over (partition by ad_group_id order by updated_at desc) = 1` keeps only the latest version before joining. Guarded by a uniqueness test on `int_snapchat_ads_details.ad_id` and by a spend reconciliation test.
- **Snapchat multi-country rows:** not duplicates. They are separate facts, so country is part of the grain and nothing is removed.

### 5.7 Materializations

| Layer | Materialization | Why |
|---|---|---|
| Staging | `view` | The data is small and the logic is a simple rename and cast. A view costs no storage, is never stale, and builds instantly |
| Intermediate | `table` | Holds join-heavy logic reused by several models. Computed once instead of on every query. `ephemeral` was rejected because ephemeral models cannot be queried or tested on their own, which weakens observability |
| `fct_marketing_ad_performance_daily` | `incremental` (microbatch, monthly, one-month lookback) | See below |
| `fct_marketing_spend`, `dim_marketing_campaigns` | `table` | Small, read often by analysts and dashboards, so they should be pre-computed |

**Why incremental, honestly:** about 95,000 rows does not need it. It is chosen for scalability: a real ad platform adds rows daily and **restates recent days**. Microbatch reprocesses only recent months and replaces them atomically, so restatements are absorbed without duplicates. A one-month `lookback` re-runs the previous month on every run. Monthly batches keep the first build to a few dozen queries instead of over a thousand daily ones. A full rebuild is `dbt build --full-refresh`.

### 5.8 Business definitions

| Metric | Definition | When undefined |
|---|---|---|
| CTR | clicks / impressions | NULL when impressions = 0 |
| CPC | spend / clicks | NULL when clicks = 0 |
| CPM | spend / impressions x 1,000 | NULL when impressions = 0 |

**Ratios are always computed from summed numerators and denominators**, never by averaging row-level ratios, because averaging would let a tiny ad count as much as a huge one. Definitions live once in dbt `docs` blocks and are reused in every model that exposes them.

### 5.9 Environment separation

The SQL never changes between environments. Only the dbt **target** changes, and two macros (`generate_schema_name`, `generate_database_name`) route models to the right catalog and schema. See [section 9](#9-environments).

### 5.10 Production authentication

Staging, CI and production authenticate as a **Databricks service principal** using OAuth machine-to-machine credentials. A personal access token exists only on a developer laptop for the `dev` target. This keeps production independent of any individual and gives the audit log a clear "the robot did this" trail.

### 5.11 CI/CD approach

GitHub Actions, because the code already lives on GitHub, no extra server is required, and its secret store keeps credentials out of the repository. Pull requests are built and tested in a throwaway schema; merging to `main` deploys production. See [section 11](#11-cicd).

---

## 6. Data model

### 6.1 Lineage

```
facebook_ads.stats      -> stg_facebook_ads_stats ------------------+
facebook_ads.ads        -> stg_facebook_ads_ads        --+          |
facebook_ads.ad_groups  -> stg_facebook_ads_ad_groups  --+--> int_facebook_ads_details --+
facebook_ads.campaigns  -> stg_facebook_ads_campaigns  --+                               |
facebook_ads.accounts   -> stg_facebook_ads_accounts   --+                               |
                                                                                         v
                                                                           int_marketing_ads_daily
                                                                                         ^
snapchat_ads.stats      -> stg_snapchat_ads_stats ------------------+                    |
snapchat_ads.ads        -> stg_snapchat_ads_ads        --+          |                    |
snapchat_ads.ad_groups  -> stg_snapchat_ads_ad_groups  --+--> int_snapchat_ads_details --+
snapchat_ads.campaigns  -> stg_snapchat_ads_campaigns  --+

int_marketing_ads_daily + seed fx_rates_to_eur -> fct_marketing_ad_performance_daily
fct_marketing_ad_performance_daily + dim_marketing_campaigns -> fct_marketing_spend
int_marketing_ads_daily -> dim_marketing_campaigns
```

The interactive version is in the generated dbt docs (`target/static_index.html`).
<p align="center">
    <img src="assets/dbt-dag (1).png" alt="DAG image" width="800">
</p>


### 6.2 Models

| Model | Layer | Grain | Materialization |
|---|---|---|---|
| `stg_facebook_ads_stats` | staging | ad x day | view |
| `stg_facebook_ads_accounts`, `_campaigns`, `_ad_groups`, `_ads` | staging | one per entity | view |
| `stg_snapchat_ads_stats` | staging | ad x day x country | view |
| `stg_snapchat_ads_ads`, `_ad_groups` (versions), `_campaigns` | staging | one per entity (ad groups: one per version) | view |
| `int_facebook_ads_details` | intermediate | ad | table |
| `int_snapchat_ads_details` | intermediate | ad | table |
| `int_marketing_ads_daily` | intermediate | platform x ad x day x country | table |
| `dim_marketing_campaigns` | mart | platform x campaign | table |
| `fct_marketing_ad_performance_daily` | mart | platform x ad x day x country | incremental |
| `fct_marketing_spend` | mart | platform x campaign x day x currency | table |
| `fx_rates_to_eur` | seed | currency | seed |

### 6.3 Main table: `fct_marketing_spend`

| Column | Meaning |
|---|---|
| `campaign_day_key` | Surrogate primary key |
| `campaign_key` | Joins to `dim_marketing_campaigns` |
| `platform` | `facebook` or `snapchat` |
| `campaign_id`, `campaign_name` | Platform campaign identifier and name |
| `ad_date` | Calendar day |
| `currency_code` | Currency of `spend`, `cpc` and `cpm` |
| `spend` | Total spend in `currency_code` |
| `spend_eur` | Total spend in euros. **Use this to compare or add across platforms** |
| `impressions`, `clicks` | Totals. Missing values count as 0 |
| `ctr`, `cpc`, `cpm` | Derived ratios. NULL when undefined |

Every model and important column has a description in YAML. For the marts these descriptions are persisted into Unity Catalog (`persist_docs`), so SQL users and AI assistants see them directly on the tables.

---

## 7. Data quality

Tests exist to protect the analytical model from bad data. When a test fails, `dbt build` skips everything downstream of it, so bad data stops before reaching the marts.

| Test | Protects against |
|---|---|
| `unique` and `not_null` on keys | Duplicate or missing rows, and joins that multiply rows |
| `unique_combination_of_columns` on each grain | Two rows for the same ad, day and country |
| `accepted_values` on `platform` (`facebook`, `snapchat`) and `currency_code` (`EUR`, `USD`) | A new platform or currency appearing unnoticed and being mis-converted |
| `spend`, `impressions`, `clicks` >= 0 | Corrupted or sign-flipped data |
| `clicks <= impressions` | Impossible rows. True of the current data, so a failure would be real news |
| `relationships` (stats to ads, ads to campaign/ad group/account, facts to dimension) | Rows pointing to things that do not exist |
| `ctr` between 0 and 1 | A broken ratio calculation |
| `spend_eur` not null | A currency missing from the exchange rate seed |
| **`assert_spend_reconciles`** (singular) | Money lost or duplicated anywhere between staging and the final fact table |
| **`assert_one_currency_per_account`** (singular) | An account reporting in two currencies, which would break conversion |
| `relationships` Snapchat ad to ad group, severity **warn** | A known, harmless gap (304 ads) should be visible but must not block the pipeline |

**Deliberate non-test:** `unique(ad_id, ad_date)` on Snapchat. It would fail on legitimate multi-country rows. The documented grain includes `country_code`.

**Tests were proven to work.** Removing the Snapchat ad group deduplication on purpose made `unique_int_snapchat_ads_details_ad_id` fail with 25 duplicated ads and caused every downstream model and test to be skipped. Restoring the fix returned the build to green. A local end-to-end run of the project (15 models, 1 seed, 81 tests) finished with 96 passes and 1 intended warning.

---

## 8. Observability with Elementary

Elementary records every dbt run and test result in its own tables and turns them into an HTML report: test results, failed tests, model run health, lineage and test history over time.

- Installed as a dbt package and as the `edr` command, pinned to the same version (`0.26.1`).
- Its tables live in a dedicated `elementary` schema (production and staging). In dev they sit beside your own models.
- Anomaly tests on `fct_marketing_spend`: `volume_anomalies` (sudden row-count jumps or drops) and `schema_changes` (columns added, removed or retyped).
- The production workflow generates `elementary_report.html` after every run and uploads it as a downloadable artifact.

**Honest limitation:** the source data is a fixed snapshot, so anomaly tests have little real history to learn from at first. The daily production schedule builds that history over time. The report is immediately useful for test results, failures, run times and lineage.

---

## 9. Environments

The same code runs in four places. Only the target changes credentials, catalog and schema.

| Environment | dbt target | Who runs it | Credentials | Where tables go |
|---|---|---|---|---|
| Development | `dev` | A developer, locally | Personal access token | `ci_development.dbt_<name>` (all models in one schema) |
| CI | `ci` | GitHub Actions, on every pull request | Service principal | `ci_development.PR_<BRANCH>`, dropped afterwards |
| Staging | `staging` | GitHub Actions, started manually | Service principal | `silver_staging.*`, `gold_staging.marketing_spend` |
| Production | `production` | GitHub Actions, on merge and daily | Service principal | `silver_production.*`, `gold_production.marketing_spend` |

Within staging and production the schemas are `staging`, `preparation`, `reference` (seeds) and `elementary` in the silver catalog, and `marketing_spend` in the gold catalog. In dev and CI everything goes into the single schema of the target, which keeps cleanup trivial.

**Why this separation:** isolation is enforced by permissions, not good intentions. A mistake in a pull request can never overwrite production tables, because CI has no write access there.

---

## 10. Security and Unity Catalog permissions

- **Production, staging and CI use a service principal** (OAuth client ID and secret). No personal access token is used outside a developer laptop.
- **Secrets** are stored in GitHub Actions secrets and read from environment variables. `profiles.yml` contains no secrets.
- **The service principal** may read `bronze_production` and may create schemas and tables only in the CI, staging and production catalogs. It cannot modify raw data.
- **Consumers** (`account users`) may read `gold_production` only.
- The service principal is also granted `CAN USE` on the SQL warehouse.

```sql
-- Replace <SP_APPLICATION_ID> with the service principal's client ID, and <your_email> with your login.
GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG bronze_production TO `<SP_APPLICATION_ID>`;

GRANT USE CATALOG, CREATE SCHEMA, CREATE TABLE ON CATALOG ci_development   TO `<SP_APPLICATION_ID>`;
GRANT USE CATALOG, CREATE SCHEMA, CREATE TABLE ON CATALOG silver_staging    TO `<SP_APPLICATION_ID>`;
GRANT USE CATALOG, CREATE SCHEMA, CREATE TABLE ON CATALOG gold_staging      TO `<SP_APPLICATION_ID>`;
GRANT USE CATALOG, CREATE SCHEMA, CREATE TABLE ON CATALOG silver_production TO `<SP_APPLICATION_ID>`;
GRANT USE CATALOG, CREATE SCHEMA, CREATE TABLE ON CATALOG gold_production   TO `<SP_APPLICATION_ID>`;

GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG ci_development TO `<your_email>`;
GRANT CREATE SCHEMA, CREATE TABLE ON CATALOG ci_development TO `<your_email>`;
GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG bronze_production TO `<your_email>`;

GRANT USE CATALOG, USE SCHEMA, SELECT ON CATALOG gold_production TO `account users`;
```

**Deliberate differences from the brief's example grants**

1. The example CI grants (`USE CATALOG`, `USE SCHEMA`, `SELECT`) are read-only, and dbt could not build anything with them. `CREATE SCHEMA` and `CREATE TABLE` were added for the CI identity.
2. `GRANT CREATE CATALOG ON METASTORE` was **omitted**. dbt never creates catalogs and they were created by an administrator, so granting it would exceed least privilege.

---

## 11. CI/CD

```
Developer -> feature branch -> pull request -> CI -> merge -> production run
```

1. A developer works on a feature branch.
2. A pull request into `main` triggers **CI** (`.github/workflows/ci.yml`): install tools, connect as the service principal, `dbt deps`, `dbt debug`, then `dbt build --fail-fast` (models, seeds and tests) into a temporary `PR_<BRANCH>` schema. The schema is always dropped afterwards by a macro that refuses to touch any schema not starting with `PR_`.
3. When CI is green the change is merged. `main` should be protected with a branch rule (pull request and passing CI required) so changes only arrive this way.
4. The merge triggers **production** (`.github/workflows/deploy_production.yml`): `dbt build` as the service principal, `dbt docs generate --static`, the Elementary report, and both uploaded as downloadable artifacts.
5. The same production workflow runs **daily at 06:00 UTC** and can also be started manually.
6. **Staging** (`.github/workflows/deploy_staging.yml`) can be started manually on any branch to rehearse a change with production-like permissions.

| Principle | How it is demonstrated |
|---|---|
| Version control | Git, feature branches, small commits |
| Pull requests | All changes reach `main` through a reviewed pull request |
| Automated validation | Build and tests on every pull request |
| Environment separation | Four targets, separate catalogs, per-pull-request schemas |
| Production deployment | Automatic on merge, plus a daily schedule |
| Secure authentication | Service principal, secrets in GitHub, no personal token |

CI rebuilds everything, which is appropriate for this data size. At larger scale, "slim CI" (build only modified models against the last production state) would cut cost and time.

---

## 12. Results: the business questions answered

All figures come from `fct_marketing_spend`, in euros (`spend_eur`). They cover **Facebook 2025-01-01 to 2025-12-31** (77 campaigns) and **Snapchat 2024-01-01 to 2024-12-02** (9 campaigns). The model holds 8,080 campaign-day rows, built from 95,109 ad-day rows.

### 12.1 Spend

| | Spend (EUR) |
|---|---|
| **Total** | **8,439,506.41** |
| Facebook | 8,408,976.87 |
| Snapchat | 30,529.54 |

Facebook's native-currency spend is split across accounts: 2,562,561.24 EUR from EUR accounts and 6,869,536.99 USD from USD accounts (5,846,415.63 EUR after conversion). USD accounts are about 69.5% of Facebook spend in euros.

**Spend by campaign: top 5**

| Platform | Campaign | Spend (EUR) |
|---|---|---|
| facebook | `gbr_app_influencer_met_retargeting_20230728_lifetime-offer-v2_website-visits` | 1,079,797.97 |
| facebook | `fra_app_influencer_tik_retargeting_20220107_seasonal-bundle-v1_installs` | 977,158.70 |
| facebook | `nld_android_display_ytb_retargeting_20250525_broad-audience-v8_signups` | 701,192.93 |
| facebook | `nld_web_paid-social_met_retargeting_20240819_live-classes-v8_installs` | 381,561.86 |
| facebook | `aut_ios_paid-social_ggl_prospecting_20211209_grammar-tips-v7_trials` | 358,051.24 |

### 12.2 Impressions

| Platform | Impressions |
|---|---|
| Facebook | 905,449,421 |
| Snapchat | 33,395,784 |

**Campaigns generating the most impressions: top 5**

| Platform | Campaign | Impressions |
|---|---|---|
| facebook | `usa_ios_display_ggl_awareness_20230916_interest-stack-v3_video-views` | 84,021,461 |
| facebook | `gbr_app_influencer_met_retargeting_20230728_lifetime-offer-v2_website-visits` | 83,532,872 |
| facebook | `fra_app_influencer_tik_retargeting_20220107_seasonal-bundle-v1_installs` | 69,807,956 |
| facebook | `nld_android_display_ytb_retargeting_20250525_broad-audience-v8_signups` | 52,997,226 |
| facebook | `nld_web_paid-social_met_retargeting_20240819_live-classes-v8_installs` | 49,039,743 |

### 12.3 Clicks

| Platform | Clicks |
|---|---|
| Facebook | 5,737,710 |
| Snapchat | 19,012 |

**Facebook generated more clicks**, about 300 times as many, reflecting a much larger spend.

**Campaigns with the most clicks: top 5**

| Platform | Campaign | Clicks | Spend (EUR) |
|---|---|---|---|
| facebook | `usa_ios_display_ggl_awareness_20230916_interest-stack-v3_video-views` | 1,389,414 | 147,514.06 |
| facebook | `aut_ios_paid-social_ggl_prospecting_20211209_grammar-tips-v7_trials` | 421,547 | 358,051.24 |
| facebook | `ita_ios_paid-social_ytb_ua_20250914_word-of-day-v6_installs` | 318,750 | 78,326.12 |
| facebook | `usa_android_paid-social_ggl_ua_20260905_podcast-launch-v2_video-views` | 263,306 | 98,105.41 |
| facebook | `gbr_app_influencer_met_retargeting_20230728_lifetime-offer-v2_website-visits` | 254,432 | 1,079,797.97 |

### 12.4 Performance metrics

| Platform | CTR | CPC (EUR) | CPM (EUR) |
|---|---|---|---|
| Facebook | 0.6337% | 1.4656 | 9.2871 |
| Snapchat | 0.0569% | 1.6058 | 0.9142 |

**How platforms differ**

- Facebook's click-through rate is roughly 11 times Snapchat's.
- Snapchat impressions are far cheaper (about 0.91 EUR per thousand against 9.29 EUR on Facebook), but they convert to clicks much less often, so the cost per click ends up similar (1.61 EUR against 1.47 EUR).
- Campaign efficiency varies widely inside Facebook. The most-clicked campaign delivered clicks at about 0.11 EUR each, while the highest-spend campaign delivered them at about 4.24 EUR each.
- Among campaigns with at least 1 million impressions, the highest CTR is `usa_android_paid-social_ggl_ua_20260905_podcast-launch-v2_video-views` at 3.09%.

**Zero handling.** 312 of the 8,080 campaign-days have zero clicks (CPC is NULL) and 311 have zero impressions (CTR and CPM are NULL). They are excluded from ratios instead of being reported as 0. Missing click values were treated as zero clicks and flagged in `is_clicks_imputed`: 24,337 Facebook and 111 Snapchat ad-day rows.

### 12.5 Performance over time

**Facebook monthly spend, 2025 (EUR)**

| Month | Spend | Month | Spend |
|---|---|---|---|
| 2025-01 | 1,125,527 | 2025-07 | 756,135 |
| 2025-02 | 660,411 | 2025-08 | 632,933 |
| 2025-03 | 706,996 | 2025-09 | 555,129 |
| 2025-04 | 536,444 | 2025-10 | 553,671 |
| 2025-05 | 760,029 | 2025-11 | 767,621 |
| 2025-06 | 700,238 | 2025-12 | 653,843 |

Spend peaked in January 2025 (1,125,527 EUR), fell to its lowest in April, and had a second, smaller peak in November.

**Snapchat monthly spend, 2024 (EUR)**

| Month | Spend |
|---|---|
| 2024-01 | 7,052 |
| 2024-02 | 9,166 |
| 2024-03 | 4,659 |
| 2024-06 | 599 |
| 2024-07 | 5,905 |
| 2024-08 | 944 |
| 2024-09 | 798 |
| 2024-11 | 1,200 |
| 2024-12 | 206 (data ends 2 December) |

There is no Snapchat data in April, May or October 2024.

**Snapchat by country**

| Country | Spend (EUR) | Impressions | Clicks |
|---|---|---|---|
| DE | 18,558.68 | 11,612,688 | 7,237 |
| CH | 7,607.66 | 14,878,208 | 7,412 |
| AT | 4,363.16 | 6,904,857 | 4,363 |
| US | 0.03 | 31 | 0 |

### 12.6 How to interpret these results

1. **The platforms do not overlap in time.** Facebook covers 2025 and Snapchat 2024, so there is no month where both have data. Compare totals and ratios, not month against month, and do not read the difference in volume as a platform comparison.
2. **"Last month" questions return nothing**, because the data ends in December 2025 (Facebook) and early December 2024 (Snapchat). Questions about recent periods should anchor on `max(ad_date)`, not today's date.
3. **Scale differs enormously.** Snapchat is about 0.4% of total spend. Rates (CTR, CPC, CPM) are the fair comparison.
4. **The euro figures depend on one exchange rate** (see limitations).

### 12.7 Reproduce the results

```sql
-- Totals and ratios per platform (swap the catalog and schema for the environment you use)
SELECT platform,
       round(sum(spend_eur), 2)                                      AS spend_eur,
       sum(impressions)                                              AS impressions,
       sum(clicks)                                                   AS clicks,
       round(sum(clicks) / nullif(sum(impressions), 0), 6)           AS ctr,
       round(sum(spend_eur) / nullif(sum(clicks), 0), 4)             AS cpc_eur,
       round(sum(spend_eur) / nullif(sum(impressions), 0) * 1000, 4) AS cpm_eur
FROM gold_production.marketing_spend.fct_marketing_spend
GROUP BY platform
ORDER BY platform;

-- Top campaigns by clicks
SELECT platform, campaign_name, sum(clicks) AS clicks, round(sum(spend_eur), 2) AS spend_eur
FROM gold_production.marketing_spend.fct_marketing_spend
GROUP BY platform, campaign_name
ORDER BY clicks DESC
LIMIT 10;

-- Spend over time
SELECT date_trunc('month', ad_date) AS month, platform, round(sum(spend_eur), 2) AS spend_eur
FROM gold_production.marketing_spend.fct_marketing_spend
GROUP BY 1, 2
ORDER BY 1, 2;
```

### 12.8 Natural-language questions

The model is designed so an AI assistant can answer questions such as "How much did we spend on Facebook?", "Which campaign had the most clicks?" and "Compare Facebook and Snapchat spend". Plain column names, persisted descriptions in Unity Catalog, explicit metric definitions, a single comparable currency column and enforced tests make the answers trustworthy. Assistants should be told the data's date range, since "last month" is not meaningful for this snapshot.

---

## 13. How to run it

**Prerequisites:** Git, Python 3.11 or 3.12, a Databricks workspace with Unity Catalog and a SQL warehouse, the raw tables loaded into `bronze_production.cdc_staging`, and the catalogs and grants from [section 10](#10-security-and-unity-catalog-permissions).

Raw tables expected in `bronze_production.cdc_staging`: `facebook_ads_stats`, `facebook_ads_accounts`, `facebook_ads_campaigns`, `facebook_ads_ad_groups`, `facebook_ads`, `snapchat_ads_stats`, `snapchat_ads_ads`, `snapchat_ads_ad_groups`, `snapchat_ads_campaigns`. Keep ID columns as text or bigint, never decimal.

```bash
# 1. Install (Mac/Linux shown; on Windows use: python -m venv .venv  and  .venv\Scripts\Activate.ps1)
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 2. Configure your own development connection (a personal token is for dev only)
export DATABRICKS_HOST="<workspace host without https://>"
export DATABRICKS_HTTP_PATH="<SQL warehouse HTTP path>"
export DATABRICKS_PAT_TOKEN="<your personal access token>"
export DEV_SCHEMA="dbt_<yourname>"

# 3. Build and test
cd marketing_platform
dbt deps
dbt debug
dbt build

# 4. Documentation and lineage
dbt docs generate --static        # opens as target/static_index.html

# 5. Observability report
edr report --profiles-dir . --open-browser false
```

To run another environment, export `DBX_ID_APPLICATION_ID` and `DBX_SECRET` for the service principal and set `DBT_TARGET`, for example `DBT_TARGET=staging dbt build`. To rebuild the incremental fact from scratch, use `dbt build --full-refresh`.

**Required GitHub secrets:** `DATABRICKS_HOST`, `DATABRICKS_HTTP_PATH`, `DBX_ID_APPLICATION_ID`, `DBX_SECRET`.

---

## 14. Repository structure

```
.
├── .github/workflows/
│   ├── ci.yml                      pull request validation
│   ├── deploy_staging.yml          manual staging rehearsal
│   └── deploy_production.yml       production deployment
├── requirements.txt                dbt, dbt-databricks, Elementary (pinned)
├── README.md
└── marketing_platform/             dbt project
    ├── dbt_project.yml             layer schemas and materializations
    ├── profiles.yml                four targets, no secrets (environment variables)
    ├── packages.yml                dbt_utils, elementary
    ├── macros/                     generate_schema_name, generate_database_name, drop_pr_schema
    ├── seeds/                      fx_rates_to_eur.csv
    ├── models/
    │   ├── staging/{facebook,snapchat}/
    │   ├── intermediate/
    │   └── marts/                  includes docs.md with metric definitions
    └── tests/singular/             spend reconciliation, one currency per account
```

---

## 15. Known limitations and assumptions

| Limitation or assumption | Impact and how to improve |
|---|---|
| **One exchange rate for all of 2025.** USD is converted at 0.851064 EUR (ECB, 31 Dec 2025, 1 EUR = 1.1750 USD). The ECB rate on 2 January 2025 was 1.0321 | Dollar spend early in the year is understated in euros by about 14%. Using monthly rates (a `month_start` column joined on month) would be more accurate |
| **Missing clicks are treated as zero** | Inferred from the data (24,337 missing against 42 explicit zeros). Flagged per row in `is_clicks_imputed` so it can be audited or reversed |
| **Facebook and Snapchat cover different years** | Direct period-over-period platform comparison is not possible. Compare rates, not volumes |
| **Snapchat has no account table** | Currency is read from each stats row. Account name is not available for Snapchat |
| **304 Snapchat ads point to ad groups missing from the export** | No performance data is attached to them. The check warns instead of failing |
| **No source freshness checks** | The data is a fixed snapshot, so a freshness check would fail permanently. A live feed should add one |
| **Incremental processing is chosen for scale, not necessity** | About 95,000 rows would also fit a plain table. If microbatch misbehaves on a given warehouse, `materialized='table'` is a safe fallback |
| **Anomaly detection has little history on a static snapshot** | Builds up with the daily production run |
| **Campaign names differ in format between platforms** | There is no reliable cross-platform campaign mapping, so none was invented. Campaigns are compared by platform, not matched across platforms |

---

## 16. Future work

- Monthly (or daily) exchange rates from a maintained source, in place of the single seed rate
- Slim CI that builds only changed models against the last production state
- A live ingestion path (Auto Loader or the platforms' APIs) instead of manual CSV uploads, with freshness checks
- Additional ad platforms through the same staging-to-unified pattern
- A cross-platform campaign mapping table if marketing adopts a shared naming convention
- A semantic layer defining metrics once for BI tools and AI assistants
