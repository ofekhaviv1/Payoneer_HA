-- Goal C — Top 10 Countries by USD Payment Volume

-- country rule: countryid (country of residence) from dim_accountholder.
-- rationale: regulatory reporting follows residence jurisdiction,
--            not birth country. see Part 1 — Finance Assumptions.
-- usd conversion: same fx logic as goal b (exact date join, NUMERIC precision).
-- coverage: goal a confirmed 0 payments with missing fx, holder, or residence country.

with fx as (
    -- usd-base rates only, parse string date to DATE for joining
    select
        sellcurrency,
        parse_date('%d-%b-%Y', quotetime) as quote_date,
        cast(ratemid as numeric) as ratemid

    from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
    where buycurrency = 'USD'
),

payments_usd as (
    -- convert each payment to usd and attach the holder's country of residence
    select
        a.countryid,
        cast(p.amount as numeric) / nullif(fx.ratemid, 0) as amount_usd

    from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments` p
    left join fx
        on  p.currency = fx.sellcurrency
        and p.paymentdate = fx.quote_date
    left join `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder` a
        on p.accountholderid = a.accountholderid
)

-- tie-break: countryname asc ensures deterministic ranking when two countries share the same total.
-- total_usd rounded to whole dollars for display; ranking uses full-precision sum.
select
    row_number() over (order by sum(p.amount_usd) desc, c.countryname asc) as rank,
    c.countryname as country,
    count(*) as payment_count,
    round(sum(p.amount_usd), 0) as total_usd

from payments_usd p
left join `payoneer-496709`.`payoneer_dev_raw`.`dim_Countries` c
    on p.countryid = c.countryid
group by c.countryname
order by total_usd desc
limit 10
