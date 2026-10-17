select
    cast(ad_group_id as string)             as ad_group_id,
    ad_group_name,
    cast(ad_group_updated_at as timestamp)  as updated_at
from {{ source('facebook_ads', 'ad_groups') }}