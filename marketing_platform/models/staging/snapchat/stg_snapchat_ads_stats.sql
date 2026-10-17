select
    'snapchat'                              as platform,
    cast(ad_detail_id as string)            as ad_id,
    cast(ad_date as date)                   as ad_date,
    upper(ad_country)                       as country_code,
    upper(ad_currency_code)                 as currency_code,
    try_cast(ad_spend as decimal(18, 6))    as spend,
    try_cast(ad_impressions as bigint)      as impressions,
    try_cast(ad_clicks as bigint)           as clicks
from {{ source('snapchat_ads', 'stats') }}