select
    cast(ad_id as string)                       as ad_id,
    cast(ad_group_id as string)                 as ad_group_id,
    ad_name,
    cast(ad_detail_updated_at as timestamp)     as updated_at
from {{ source('snapchat_ads', 'ads') }}