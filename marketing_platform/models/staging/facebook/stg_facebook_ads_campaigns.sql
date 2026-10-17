select
    cast(campaign_id as string)             as campaign_id,
    campaign_name,
    cast(campaign_updated_at as timestamp)  as updated_at
from {{ source('facebook_ads', 'campaigns') }}