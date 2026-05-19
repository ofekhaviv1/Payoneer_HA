-- DATA ASSURANCE TESTS — Goal A
-- Dataset : payoneer-496709.payoneer_dev_raw
--
-- Risk coverage & QA checks:
--   - Primary keys are unique and non-null (fan-out prevention)
--   - Referential integrity: foreign keys resolve to valid parent rows (join safety)
--   - BuyCurrency is strictly USD (fx convention enforcement)
--   - (SellCurrency, QuoteTime) grain is unique (no rate duplication)
--   - Every (currency, paymentdate) pair has an fx rate (goal b coverage)
--   - Amount > 0 (preventing corrupted aggregations)


-- dim_Countries
-- Primary key integrity — CountryID is the lookup key for all
-- country joins in goal c and cross-border logic in goal d.

-- QA Check: Ensure CountryID is unique
with pk_check as (
  select CountryID as unique_field
  from `payoneer-496709`.`payoneer_dev_raw`.`dim_Countries`
  where CountryID is not null
)
select unique_field, count(*) as n_records
from pk_check
group by unique_field
having count(*) > 1;


-- QA Check: Verify no missing values in CountryID
select CountryID
from `payoneer-496709`.`payoneer_dev_raw`.`dim_Countries`
where CountryID is null;


-- QA Check: Verify no missing values in CountryName
select CountryName
from `payoneer-496709`.`payoneer_dev_raw`.`dim_Countries`
where CountryName is null;


-- dim_AccountHolder
-- PK and FK integrity — every payment must trace to a
-- holder with valid residence and birth country for goals c and d.

-- QA Check: Ensure AccountHolderID is unique
with pk_check as (
  select AccountHolderID as unique_field
  from `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder`
  where AccountHolderID is not null
)
select unique_field, count(*) as n_records
from pk_check
group by unique_field
having count(*) > 1;


-- QA Check: Verify no missing values in AccountHolderID
select AccountHolderID
from `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder`
where AccountHolderID is null;


-- QA Check: Verify no missing values in FirstName
select FirstName
from `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder`
where FirstName is null;


-- QA Check: Verify no missing values in LastName
select LastName
from `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder`
where LastName is null;


-- QA Check: Verify no missing residence countries
-- a null residence country would exclude the holder from goal c volume reporting.
select CountryID
from `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder`
where CountryID is null;


-- QA Check: Verify no missing values in City
select City
from `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder`
where City is null;


-- QA Check: Verify no missing birth countries
-- a null birth country makes cross-border classification in goal d impossible.
select BirthCountryID
from `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder`
where BirthCountryID is null;


-- QA Check: Referential Integrity — Residence Country lookup
-- ensures every residence country resolves to a known country name.
with child as (
    select CountryID as from_field
    from `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder`
    where CountryID is not null
),
parent as (
    select CountryID as to_field
    from `payoneer-496709`.`payoneer_dev_raw`.`dim_Countries`
)
select from_field
from child
left join parent on child.from_field = parent.to_field
where parent.to_field is null;


-- QA Check: Referential Integrity — Birth Country lookup
-- ensures every birth country resolves to a known country name.
with child as (
    select BirthCountryID as from_field
    from `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder`
    where BirthCountryID is not null
),
parent as (
    select CountryID as to_field
    from `payoneer-496709`.`payoneer_dev_raw`.`dim_Countries`
)
select from_field
from child
left join parent on child.from_field = parent.to_field
where parent.to_field is null;



-- dim_Currency_Quotes
-- FX rate integrity — the join grain (SellCurrency, QuoteTime) must
-- be unique under BuyCurrency=USD to prevent row duplication.


-- QA Check: Composite key uniqueness (SellCurrency, QuoteTime)
-- duplicate (currency, date) pairs would cause fan-out in the goal b left join,
-- multiplying payment rows and inflating usd totals.
with validation_errors as (
    select SellCurrency, QuoteTime
    from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
    group by SellCurrency, QuoteTime
    having count(*) > 1
)
select * from validation_errors;


-- QA Check: Verify no missing values in BuyCurrency
select BuyCurrency
from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
where BuyCurrency is null;


-- QA Check: Data Domain Validation — BuyCurrency must be 'USD'
-- all fx logic depends on this convention; any non-USD buy currency would break goal b.
with all_values as (
    select
        BuyCurrency as value_field,
        count(*) as n_records
    from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
    group by BuyCurrency
)
select *
from all_values
where value_field not in ('USD');


-- QA Check: Verify no missing values in SellCurrency
select SellCurrency
from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
where SellCurrency is null;


-- QA Check: Verify no missing values in QuoteTime
select QuoteTime
from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
where QuoteTime is null;


-- QA Check: Verify no missing values in RateMid
-- a null rate would cause nullif(ratemid, 0) to propagate null into amount_usd.
select RateMid
from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
where RateMid is null;


-- fact_Payments
-- Payment integrity — every payment must have a valid holder,
-- a convertible currency, and a strictly positive amount.


-- QA Check: Ensure PaymentID is unique
with pk_check as (
  select PaymentID as unique_field
  from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments`
  where PaymentID is not null
)
select unique_field, count(*) as n_records
from pk_check
group by unique_field
having count(*) > 1;


-- QA Check: Verify no missing values in PaymentID
select PaymentID
from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments`
where PaymentID is null;


-- QA Check: Verify no missing values in Amount
select Amount
from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments`
where Amount is null;


-- QA Check: Logical constraint — Amount must be strictly positive
-- negative or zero amounts would silently corrupt usd aggregations in goals b-f.
select 1
from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments`
where not(Amount > 0);


-- QA Check: Verify no missing values in Currency
select Currency
from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments`
where Currency is null;


-- QA Check: Verify no missing values in PaymentDate
select PaymentDate
from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments`
where PaymentDate is null;


-- QA Check: Verify no missing values in AccountHolderID
select AccountHolderID
from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments`
where AccountHolderID is null;


-- QA Check: Referential Integrity — Orphan payments check
-- orphan payments (no matching holder) would lose country and cross-border context.
with child as (
    select AccountHolderID as from_field
    from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments`
    where AccountHolderID is not null
),
parent as (
    select AccountHolderID as to_field
    from `payoneer-496709`.`payoneer_dev_raw`.`dim_AccountHolder`
)
select from_field
from child
left join parent on child.from_field = parent.to_field
where parent.to_field is null;


-- QA Check: Referential Integrity — Currency exists in FX table
-- a payment currency absent from the fx table cannot be converted to usd.
-- note: this confirms the currency exists in the fx table but does not guarantee
-- a rate exists for every (currency, paymentdate) pair — see test below.
with child as (
    select Currency as from_field
    from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments`
    where Currency is not null
),
parent as (
    select SellCurrency as to_field
    from `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes`
)
select from_field
from child
left join parent on child.from_field = parent.to_field
where parent.to_field is null;


-- QA Check: FX rate coverage (Missing rates per payment date)
-- this is the exact join goal b uses. a payment without a rate on its date
-- returns null amount_usd and is silently excluded from all usd aggregations.
-- expected result: 0 rows (all payments should have a matching fx rate).
select
    p.paymentid,
    p.currency,
    p.paymentdate
from `payoneer-496709`.`payoneer_dev_raw`.`fact_Payments` p
left join `payoneer-496709`.`payoneer_dev_raw`.`dim_Currency_Quotes` q
    on  q.buycurrency = 'USD'
    and q.sellcurrency = p.currency
    and parse_date('%d-%b-%Y', q.quotetime) = p.paymentdate
where q.ratemid is null;