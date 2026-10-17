select
    {{ dbt_utils.generate_surrogate_key(['f.platform', 'f.campaign_id', 'f.ad_date', 'f.currency_code']) }} as campaign_day_key,
    f.campaign_key,
    f.platform,
    f.campaign_id,
    c.campaign_name,
    f.ad_date,
    f.currency_code,
    sum(f.spend)                                            as spend,
    sum(f.spend_eur)                                        as spend_eur,
    sum(f.impressions)                                      as impressions,
    sum(f.clicks)                                           as clicks,
    sum(f.clicks) / nullif(sum(f.impressions), 0)           as ctr,
    sum(f.spend) / nullif(sum(f.clicks), 0)                 as cpc,
    sum(f.spend) / nullif(sum(f.impressions), 0) * 1000     as cpm
from {{ ref('fct_marketing_ad_performance_daily') }} as f
left join {{ ref('dim_marketing_campaigns') }} as c
    on f.campaign_key = c.campaign_key
group by all;