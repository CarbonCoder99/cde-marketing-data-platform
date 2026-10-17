with ad_groups_latest as (

    select *
    from {{ ref('stg_snapchat_ads_ad_groups') }}
    qualify row_number() over (
        partition by ad_group_id
        order by updated_at desc
    ) = 1

)

select
    a.ad_id,
    a.ad_name,
    a.ad_group_id,
    g.ad_group_name,
    g.campaign_id,
    c.campaign_name,
    c.account_id
from {{ ref('stg_snapchat_ads') }} as a
left join ad_groups_latest as g on a.ad_group_id = g.ad_group_id
left join {{ ref('stg_snapchat_ads_campaigns') }} as c on g.campaign_id = c.campaign_id