{% docs ctr %}
Click-through rate = clicks / impressions. NULL when impressions = 0.
{% enddocs %}

{% docs cpc %}
Cost per click = spend / clicks, in the account's own currency. NULL when clicks = 0.
{% enddocs %}

{% docs cpm %}
Cost per 1,000 impressions = spend / impressions * 1000, in the account's own currency.
NULL when impressions = 0.
{% enddocs %}

{% docs spend_eur %}
Spend converted to euros using the rate in the fx_rates_to_eur seed.
Use this column to compare or add up spend across accounts and platforms.
{% enddocs %}