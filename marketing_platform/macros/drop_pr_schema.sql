{% macro drop_pr_schema() %}
    {% if not target.schema.startswith('PR_') %}
        {{ exceptions.raise_compiler_error("Refusing to drop schema " ~ target.schema ~ " because it does not start with PR_") }}
    {% endif %}
    {% do run_query("drop schema if exists " ~ target.database ~ "." ~ target.schema ~ " cascade") %}
    {{ log("Dropped schema " ~ target.database ~ "." ~ target.schema, info=True) }}
{% endmacro %}