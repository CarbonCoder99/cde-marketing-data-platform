{{ config(event_time='ad_date') }}

with facebook as (

    select
        s.platform,
        s.ad_id,
        d.ad_name,
        d.ad_group_id,
        d.ad_group_name,
        d.campaign_id,
        d.campaign_name,
        d.account_id,
        s.ad_date,
        s.country_code,
        d.currency_code,
        s.spend,
        s.impressions,
        s.clicks
    from {{ ref('stg_facebook_ads_stats') }} as s
    left join {{ ref('int_facebook_ads_details') }} as d on s.ad_id = d.ad_id

),

snapchat as (

    select
        s.platform,
        s.ad_id,
        d.ad_name,
        d.ad_group_id,
        d.ad_group_name,
        d.campaign_id,
        d.campaign_name,
        d.account_id,
        s.ad_date,
        s.country_code,
        s.currency_code,
        s.spend,
        s.impressions,
        s.clicks
    from {{ ref('stg_snapchat_ads_stats') }} as s
    left join {{ ref('int_snapchat_ads_details') }} as d on s.ad_id = d.ad_id

)

select * from facebook
union all
select * from snapchat