/*
    Dungeons and Dragons

    This game uses dice with a variety of sides, including:

    - 4-sided dice
    - 6-sided dice
    - 8-sided dice
    - 10-sided dice
    - 12-sided dice
    - 20-sided dice

    The selection of dice that are rolled at any time can vary.
*/

drop schema if exists dungeons_and_dragons cascade;
create schema dungeons_and_dragons;
use dungeons_and_dragons;


/* The dice in this game */
create or replace table dice (
    sides integer,
    face  integer,
    primary key (sides, face)
);
insert into dice
    with
    sides(sides) as (values (4), (6), (8), (10), (12), (20)),
    faces(face) as (from generate_series(1, 20))

    select
        sides.sides,
        faces.face
    from sides
        left join faces
            on sides.sides >= faces.face
    order by
        sides.sides,
        faces.face
;


------------------------------------------------------------------------
------------------------------------------------------------------------

/* Outcome probabilities for rolling 20 at advantage and disadvantage */
create or replace table twenty_sided_die_vantages (
    face                       integer primary key,
    likelihood                 numeric(6, 4),
    likelihood_at_advantage    numeric(6, 4),
    likelihood_at_disadvantage numeric(6, 4),
);

insert into twenty_sided_die_vantages
    with

    twenty_sided_die as (select face from dice where sides = 20),

    advantages as (
        select
            greatest(d1.face, d2.face) as face,
            count(*) / sum(count(*)) over () as likelihood_at_advantage,
        from twenty_sided_die as d1
            cross join twenty_sided_die as d2
        group by all
    ),

    disadvantages as (
        select
            least(d1.face, d2.face) as face,
            count(*) / sum(count(*)) over () as likelihood_at_disadvantage,
        from twenty_sided_die as d1
            cross join twenty_sided_die as d2
        group by all
    )

    select
        twenty_sided_die.face,
        100.0 / count(*) over () as likelihood,
        100.0 * advantages.likelihood_at_advantage,
        100.0 * disadvantages.likelihood_at_disadvantage,
    from twenty_sided_die
        left join advantages
            using (face)
        left join disadvantages
            using (face)
    order by twenty_sided_die.face
;


/* Twenty-sided die vantages (better as a line graph) */
select
    face,
    likelihood,
    likelihood_at_advantage,
    likelihood_at_disadvantage
from twenty_sided_die_vantages
order by face
;
