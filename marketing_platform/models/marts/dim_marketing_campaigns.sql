select
    {{ dbt_utils.generate_surrogate_key(['platform', 'campaign_id']) }} as campaign_key,
    platform,
    campaign_id,
    campaign_name,
    account_id
from {{ ref('int_marketing_ads_daily') }}
group by platform, campaign_id, campaign_name, account_id