--Goal B — USD Normalization


-- option 1 — exact date join
-- joins each payment to the fx rate on the exact payment date.
-- suitable when the fx table has full daily coverage (verified: 0 gaps).
-- in production use option 2.

with fx as (
    -- filter to usd-base rates only and parse the date string into DATE.
    -- cast ratemid to NUMERIC here so all downstream arithmetic
    -- inherits exact decimal precision from the source.
    select
        sellcurrency,
        parse_date('%d-%b-%Y', quotetime) as quote_date,
        cast(ratemid as numeric) as ratemid

    from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
    where buycurrency = 'USD'
),

payments_with_usd as (
    select
        p.paymentid,
        p.accountholderid,
        p.amount,
        p.currency,
        p.paymentdate,
        fx.ratemid,

        -- cast amount to NUMERIC before division to preserve exact decimal arithmetic.
        -- NULLIF(ratemid, 0) prevents a division-by-zero runtime exception
        -- if a corrupted fx row carries a zero rate.
        -- no rounding here — rounding is deferred to the presentation layer
        -- to avoid accumulation of rounding errors in downstream aggregations.
        cast(p.amount as numeric) / nullif(fx.ratemid, 0) as amount_usd,

        case
            when fx.ratemid is null then 'no fx rate found'
            else 'converted'
        end as conversion_status

    from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments` p
    left join fx
        on  p.currency = fx.sellcurrency
        and p.paymentdate = fx.quote_date
)

-- per-payment output: paymentid, original amount, currency, fx date (= payment date for exact join), ratemid, amount_usd.
-- coverage verified: select conversion_status, count(*) from payments_with_usd group by 1
--   → converted = 3000 | no fx rate found = 0
select
    paymentid,
    accountholderid,
    amount,
    currency,
    paymentdate as fx_date,
    ratemid,
    amount_usd,
    conversion_status
from payments_with_usd
order by paymentid;


-- option 2 — last known rate (production-safe fallback)
-- if no rate exists for the exact payment date, uses the most
-- recent available rate on or before that date.
-- more robust for production where daily fx coverage is not guaranteed.

with fx as (
    select
        sellcurrency,
        parse_date('%d-%b-%Y', quotetime)  as quote_date,
        cast(ratemid as numeric) as ratemid

    from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
    where buycurrency = 'USD'
)

    select
        p.paymentid,
        p.accountholderid,
        p.amount,
        p.currency,
        p.paymentdate,
        fx.quote_date as applied_fx_date,
        fx.ratemid,
        cast(p.amount as numeric) / nullif(fx.ratemid, 0) as amount_usd

    from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments` p
    -- bring all fx rates on or before the payment date
    left join fx
        on  p.currency = fx.sellcurrency
        and fx.quote_date <= p.paymentdate
    -- keep only the closest available rate (most recent date <= payment date)
    qualify row_number() over (partition by p.paymentid order by fx.quote_date desc) = 1;
