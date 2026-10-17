select
    cast(account_id as string)              as account_id,
    account_name,
    upper(ad_currency_code)                 as currency_code,
    cast(account_updated_at as timestamp)   as updated_at
from {{ source('facebook_ads', 'accounts') }}