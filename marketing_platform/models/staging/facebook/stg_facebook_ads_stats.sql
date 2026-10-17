select
    'facebook'                              as platform,
    cast(ad_id as string)                   as ad_id,
    cast(ad_date as date)                   as ad_date,
    cast(null as string)                    as country_code,
    try_cast(ad_spend as decimal(18, 6))    as spend,
    try_cast(ad_impressions as bigint)      as impressions,
    try_cast(ad_clicks as bigint)           as clicks
from {{ source('facebook_ads', 'stats') }}