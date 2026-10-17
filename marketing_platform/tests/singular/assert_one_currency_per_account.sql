-- Fails (returns rows) if any account reports spend in more than one currency.
select
    platform,
    account_id,
    count(distinct currency_code) as currencies
from {{ ref('int_marketing_ads_daily') }}
group by platform, account_id
having count(distinct currency_code) > 1