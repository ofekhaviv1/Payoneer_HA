-- Goal E — Top Three Payments per Account
--
-- for each account holder, returns up to three largest payments by usd value.
-- holders with fewer than 3 payments appear with only as many rows as they have.
-- usd conversion: same fx logic as goal b (exact date join, NUMERIC precision).
-- goal a confirmed 0 payments without an fx rate, so amount_usd is never null here.
--
-- tie-breaking: when two payments share the same amount_usd, the most recent
-- payment ranks first (paymentdate desc) — recency is the most natural business
-- tiebreaker for a "top payments" report.
-- alternative: paymentid asc alone gives pure determinism without a business preference;
-- paymentdate desc is chosen here because a recent payment is a more meaningful "top" entry.
-- paymentid asc is the secondary tiebreaker for same-date ties, guaranteeing full determinism.

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
        p.paymentid,
        p.accountholderid,
        p.amount,
        p.currency,
        p.paymentdate,
        cast(p.amount as numeric) / nullif(fx.ratemid, 0) as amount_usd

    from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments` p
    left join fx
        on  p.currency = fx.sellcurrency
        and p.paymentdate = fx.quote_date
),

ranked as (
    -- row_number gives at most 3 rows per holder; rank/dense_rank could return more on ties.
    select
        paymentid,
        accountholderid,
        paymentdate,
        amount,
        currency,
        round(amount_usd, 2) as amount_usd,
        row_number() over (partition by accountholderid order by amount_usd desc, paymentdate desc, paymentid asc) as payment_rank

    from payments_usd
)

select
    accountholderid,
    payment_rank,
    paymentid,
    paymentdate,
    amount,
    currency,
    amount_usd

from ranked
where payment_rank <= 3
order by accountholderid, payment_rank
