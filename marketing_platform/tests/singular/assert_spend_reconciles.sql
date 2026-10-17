-- Fails (returns rows) if total spend per platform differs between staging and the final fact table.
-- Catches rows lost or duplicated by a join.
with staged as (

    select platform, sum(spend) as spend from {{ ref('stg_facebook_ads_stats') }} group by platform
    union all
    select platform, sum(spend) as spend from {{ ref('stg_snapchat_ads_stats') }} group by platform

),

modelled as (

    select platform, sum(spend) as spend from {{ ref('fct_marketing_ad_performance_daily') }} group by platform

)

select
    s.platform,
    s.spend as staged_spend,
    m.spend as modelled_spend
from staged as s
left join modelled as m on s.platform = m.platform
where m.spend is null
   or abs(s.spend - m.spend) > 0.01