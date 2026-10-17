select
    a.ad_id,
    a.ad_name,
    a.ad_status,
    a.ad_group_id,
    g.ad_group_name,
    a.campaign_id,
    c.campaign_name,
    a.account_id,
    acc.account_name,
    acc.currency_code
from {{ ref('stg_facebook_ads') }} as a
left join {{ ref('stg_facebook_ads_ad_groups') }} as g on a.ad_group_id = g.ad_group_id
left join {{ ref('stg_facebook_ads_campaigns') }} as c on a.campaign_id = c.campaign_id
left join {{ ref('stg_facebook_ads_accounts') }} as acc on a.account_id = acc.account_id