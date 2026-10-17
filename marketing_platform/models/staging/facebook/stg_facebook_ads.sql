select
    cast(ad_id as string)                   as ad_id,
    cast(campaign_id as string)             as campaign_id,
    cast(ad_group_id as string)             as ad_group_id,
    cast(account_id as string)              as account_id,
    ad_name,
    ad_status,
    cast(ad_updated_at as timestamp)        as updated_at
from {{ source('facebook_ads', 'ads') }}