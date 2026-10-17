{{ config(
    materialized='incremental',
    incremental_strategy='microbatch',
    event_time='ad_date',
    batch_size='month',
    begin='2024-01-01',
    lookback=1
) }}

select
    {{ dbt_utils.generate_surrogate_key(['d.platform', 'd.ad_id', 'd.ad_date', 'd.country_code']) }} as ad_performance_key,
    {{ dbt_utils.generate_surrogate_key(['d.platform', 'd.campaign_id']) }}                          as campaign_key,
    d.platform,
    d.ad_id,
    d.ad_name,
    d.campaign_id,
    d.account_id,
    d.ad_date,
    d.country_code,
    d.currency_code,
    d.spend,
    d.spend * fx.rate_to_eur            as spend_eur,
    coalesce(d.impressions, 0)          as impressions,
    coalesce(d.clicks, 0)               as clicks,
    d.clicks is null                    as is_clicks_imputed
from {{ ref('int_marketing_ads_daily') }} as d
left join {{ ref('fx_rates_to_eur') }} as fx
    on d.currency_code = fx.currency_code