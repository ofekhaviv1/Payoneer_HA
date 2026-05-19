-- Goal D — Cross-border vs Not Cross-border

-- definition: cross-border = account holder whose country of residence (countryid)
--             differs from their country of birth (birthcountryid).
-- rationale:  cross-border status is determined by the holder's attributes,
--             not by payment routing or recipient country.
-- usd conversion: same fx logic as goal b and c (exact date join, NUMERIC precision).
-- coverage: goal a confirmed 0 orphan payments and 0 missing countryid/birthcountryid —
--           the 'unknown' segment will be empty in this dataset.

with fx as (
    select
        sellcurrency,
        parse_date('%d-%b-%Y', quotetime) as quote_date,
        cast(ratemid as numeric) as ratemid

    from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
    where buycurrency = 'USD'
),

payments_usd as (
    -- convert each payment to usd and attach holder attributes
    select
        a.accountholderid,
        a.countryid,
        a.birthcountryid,
        cast(p.amount as numeric) / nullif(fx.ratemid, 0) as amount_usd

    from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments` p
    left join fx
        on  p.currency = fx.sellcurrency
        and p.paymentdate = fx.quote_date
    left join `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder` a
        on p.accountholderid = a.accountholderid
)

select
    -- null-safe classification: a holder with either country missing cannot be classified.
    case
        when countryid is null or birthcountryid is null then 'unknown'
        when countryid != birthcountryid then 'cross-border'
        else 'domestic'
    end as segment,
    count(distinct accountholderid) as holder_count,
    round(sum(amount_usd), 0) as total_usd,
    round(sum(amount_usd) / nullif(count(*), 0), 0) as avg_usd_per_payment,
    round(sum(amount_usd) / nullif(count(distinct accountholderid), 0), 0) as avg_usd_per_holder,
    round(cast(count(*) as numeric) / nullif(count(distinct accountholderid), 0), 1) as payments_per_holder

from payments_usd
group by segment
order by segment;
