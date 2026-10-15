{% macro generate_database_name(custom_database_name=none, node=none) -%}
    {%- if target.name in ['staging', 'production'] -%}
        {%- if node is not none and node.resource_type == 'model' and 'marts' in node.fqn -%}
            gold_{{ target.name }}
        {%- else -%}
            silver_{{ target.name }}
        {%- endif -%}
    {%- else -%}
        {{ target.database }}
    {%- endif -%}
{%- endmacro %}