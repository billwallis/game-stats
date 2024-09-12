/*
    Betrayal at House on the Hill

    This game uses 6-sided dice, but the dice have:

    - Two sides with 0
    - Two sides with 1
    - Two sides with 2

    This is equivalent to rolling a 3-sided die with the values 0, 1,
    and 2 (if such a die could exist).

    Up to 8 dice can be rolled at once, and the result is the sum of the
    dice.
*/

drop schema if exists betrayal_at_house_on_the_hill cascade;
create schema betrayal_at_house_on_the_hill;
use betrayal_at_house_on_the_hill;


/* The dice in this game */
create or replace table dice (
    sides integer,
    face  integer,
    primary key (sides, face)
);
insert into dice
values
    (3, 0),
    (3, 1),
    (3, 2)
;


------------------------------------------------------------------------
------------------------------------------------------------------------

/* Outcome probabilities for rolling 1 to 8 dice */
create or replace table outcome_likelihood (
    number_of_dice integer,
    outcome        integer,
    likelihood     numeric(6, 4),
    primary key (number_of_dice, outcome)
);
insert into outcome_likelihood
    with recursive

    die as (select face from dice where sides = 3),

    roll_n(n, outcome, volume) as (
            select 1, face, 1
            from die
        union all
            select
                roll_n.n + 1,
                roll_n.outcome + die.face,
                sum(roll_n.volume)
            from roll_n
                cross join die
            where roll_n.n < 8
            group by all
    )

    select
        n as number_of_dice,
        outcome,
        100.0 * volume / power(3, n) as likelihood
    from roll_n
    order by
        n,
        outcome
;


/* View outcomes for a given number of dice */
select
    outcome,
    likelihood,
    sum(likelihood) over (order by outcome) as cumulative_likelihood
from outcome_likelihood
where number_of_dice = 8
;
