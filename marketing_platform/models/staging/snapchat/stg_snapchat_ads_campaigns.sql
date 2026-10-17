select
    cast(campaign_id as string)     as campaign_id,
    cast(account_id as string)      as account_id,
    campaign_name
from {{ source('snapchat_ads', 'campaigns') }}