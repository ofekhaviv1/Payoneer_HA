-- Goal F — Month-over-Month Portfolio Trend

with fx as (
    select
        sellcurrency,
        parse_date('%d-%b-%Y', quotetime) as quote_date,
        cast(ratemid as numeric) as ratemid

    from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
    where buycurrency = 'USD'
),

payments_usd as (
    -- convert each payment to usd using the exact date join from goal b
    select
        p.paymentdate,
        cast(p.amount as numeric) / nullif(fx.ratemid, 0) as amount_usd

    from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments` p
    left join fx
        on  p.currency = fx.sellcurrency
        and p.paymentdate = fx.quote_date
),

monthly as (
    -- aggregate to calendar month
    select
        date_trunc(paymentdate, month) as payment_month,
        sum(amount_usd) as total_usd,
        count(*) as payment_count

    from payments_usd
    group by payment_month
)

select
    format_date('%Y-%m', payment_month) as month,
    payment_count,
    total_usd,

    -- lag provides the previous month's total, nullif guards against a zero base
    round(lag(total_usd) over (order by payment_month), 0) as prev_month_usd,
    round(
        (total_usd - lag(total_usd) over (order by payment_month))
        / nullif(lag(total_usd) over (order by payment_month), 0) * 100, 2) as mom_pct_change

from monthly
order by payment_month
