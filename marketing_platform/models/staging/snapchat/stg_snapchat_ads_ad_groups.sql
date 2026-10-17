select
    cast(ad_group_id as string)                 as ad_group_id,
    cast(campaign_id as string)                 as campaign_id,
    ad_group_name,
    cast(ad_group_updated_at as timestamp)      as updated_at
from {{ source('snapchat_ads', 'ad_groups') }}