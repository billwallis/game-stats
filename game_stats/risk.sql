/*
    Risk

    This game uses up to three normal 6-sided dice.

    The game has "attack" rolls and "defence" rolls. The attacker can
    roll up to three dice, and the defender can roll up to two dice.
    The highest die from each roll is compared, and the higher roll wins
    with the defender winning ties.

    Some variants of the game allow modifiers to the dice rolls.
*/

drop schema if exists risk cascade;
create schema risk;
use risk;


/* The dice in this game */
create or replace table dice (
    sides integer,
    face  integer,
    primary key (sides, face)
);
insert into dice
    with
    sides(sides) as (values (6), (8)),
    faces(face) as (from generate_series(1, 8))

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

/*
    Standard game

    Six-sided rolls only, no modifiers.
*/

/* Six-sided roll possibilities */
create or replace table roll_outcomes__standard (
    n          integer,
    outcome_id varchar,
    outcome    integer[],
    primary key (n, outcome_id)
);
insert into roll_outcomes__standard
    with recursive

    die as (from dice where sides = 6),

    rolls(n, outcome_id, outcome) as (
            select 1, face::varchar, [face]
            from die
        union all
            select
                rolls.n + 1,
                concat_ws('-', rolls.outcome_id, die.face),
                list_reverse_sort(list_append(rolls.outcome, die.face)),
            from rolls
                cross join die
            where rolls.n < 3
    )

    select *
    from rolls
    order by all
;

/* roll_outcomes__standard */
from roll_outcomes__standard
;


create or replace table scenario_outcomes__standard as
with

scenarios(attackers, defenders) as (
    select *
    from generate_series(1, 3) as attackers
        cross join generate_series(1, 2) as defenders
),

scenario_outcomes as (
    select
        scenarios.attackers,
        scenarios.defenders,
        attacker_rolls.outcome as attacker_rolls,
        defender_rolls.outcome as defender_rolls,

        coalesce(attacker_rolls.outcome[1], 0) as attacker_roll_1,
        coalesce(attacker_rolls.outcome[2], 0) as attacker_roll_2,
        coalesce(defender_rolls.outcome[1], 0) as defender_roll_1,
        coalesce(defender_rolls.outcome[2], 0) as defender_roll_2,

        (0
            + if(attacker_roll_1 > defender_roll_1, 1, 0)
            + if(attacker_roll_2 > defender_roll_2 and scenarios.defenders = 2, 1, 0)
        ) as attacks_won
    from scenarios
        left join roll_outcomes__standard as attacker_rolls
            on scenarios.attackers = attacker_rolls.n
        left join roll_outcomes__standard as defender_rolls
            on scenarios.defenders = defender_rolls.n
),

scenario_likelihoods as (
    select
        attackers,
        defenders,
        attacks_won,
        count(*) as volume,
        100.0 * count(*) / sum(count(*)) over scenario as likelihood
    from scenario_outcomes
    group by
        attackers,
        defenders,
        attacks_won
    window scenario as (partition by attackers, defenders)
),

axis as (
    select
        attackers,
        defenders,
        generate_series as attacks_won
    from scenarios
        cross join generate_series(0, 2)
)

select
    attackers,
    defenders,
    attacks_won,
    coalesce(likelihood, 0)::numeric(6, 4) as likelihood
from axis
    left join scenario_likelihoods
        using (attackers, defenders, attacks_won)
order by all
;

/* scenario_outcomes__standard */
from scenario_outcomes__standard
;


/* 8 attackers vs 6 defenders */
with recursive

outcomes as (
    select
        attackers,
        defenders,
        attacks_won,
        max(attacks_won) over (partition by attackers, defenders) - attacks_won as attacks_lost,
        likelihood
    from scenario_outcomes__standard
    where likelihood > 0
),

/* Could use some memoisation if we start from the bottom? */
battle as (
        select
            8 as attackers_remaining,
            6 as defenders_remaining,
            1::numeric(12, 10) as likelihood,
    union all
        select
            battle.attackers_remaining - outcomes.attacks_lost,
            battle.defenders_remaining - outcomes.attacks_won,
            battle.likelihood * coalesce(outcomes.likelihood / 100.0, 0),
        from battle
            inner join outcomes
                on  least(battle.attackers_remaining, 3) = outcomes.attackers
                and least(battle.defenders_remaining, 2) = outcomes.defenders
                and outcomes.attacks_won <= least(battle.attackers_remaining, battle.defenders_remaining)
)

select
    attackers_remaining,
    defenders_remaining,
    sum(likelihood) as likelihood,
    sum(sum(likelihood) filter (where attackers_remaining != 0)) over () as attackers_win_likelihood,
    sum(sum(likelihood) filter (where defenders_remaining != 0)) over () as defenders_win_likelihood,
from battle
where attackers_remaining = 0 or defenders_remaining = 0
group by attackers_remaining, defenders_remaining
order by attackers_remaining desc, defenders_remaining desc
;


------------------------------------------------------------------------
------------------------------------------------------------------------

/*
    Game of Thrones Edition

    Six or eight-sided rolls, various modifiers.

    The modifiers for the dice rolls are:

    - "Win ties" can be added to the attacker's roll
    - "+1 to highest die" can be added to the roll
    - "+1 to all dice" can be added to the roll
    - "Re-roll 1s" can be added to the roll
    - "Re-roll your lowest die" can be added to the roll
    - "Re-roll their highest dice" can be added to the roll

    TODO: Calculate the likelihoods for the three re-roll modifiers.
*/

/*
    Roll possibilities

    Note that we _don't_ care about different dice permutations, only
    the outcome permutations: we only care about _which_ dice are
    thrown, say [6, 8], not the order in which they are thrown; however,
    we do care about the order of the outcomes as these represent the
    different ways of getting the same outcome (I think).

    If we deduplicated the dice permutations (that is, didn't care about
    their permutations), then we would not weight the outcomes
    correctly.

    For example, with three 6-sided dice, the outcome [1, 1, 1] can be
    achieved in exactly one way: all dice are 1. Alternatively, the
    combination [1, 1, 2] can be achieved in three ways: with the
    permutations:

    - [1, 1, 2]
    - [1, 2, 1]
    - [2, 1, 1]

    If we didn't care about the dice permutations, then we would count
    [1, 1, 2] as having the same likelihood as [1, 1, 1], which is
    incorrect.
*/
create or replace table dice_combinations as
    with recursive combinations(combo) as (
            values ([6]), ([8])
        union all
            select list_append(combinations.combo, die.sides),
            from combinations
                left join values (6), (8) as die(sides)
                    on combinations.combo[-1] <= die.sides
            where len(combinations.combo) < 3
    )

    select len(combo) as n, combo
    from combinations
;

/* dice_combinations */
from dice_combinations
;


create or replace table roll_outcomes (
    n          integer,    /* Number of dice */
    combo_id   varchar,    /* Ordered list of dice permutations */
    outcome_id varchar,    /* Ordered list of outcome permutations */
    combo      integer[],  /* Ordered list of dice combinations */
    outcome    integer[],  /* Ordered list of outcome combinations */
    primary key (n, combo_id, outcome_id)
);
insert into roll_outcomes
    with recursive rolls(n, combo, remaining_dice, outcome_id, outcome) as (
            select
                n,
                combo,
                combo,
                null::varchar,
                [] as outcome,
            from dice_combinations
        union all
            select
                rolls.n,
                rolls.combo,
                rolls.remaining_dice[2:],
                concat_ws('-', rolls.outcome_id, dice.face::varchar),
                list_reverse_sort(list_append(rolls.outcome, dice.face)),
            from rolls
                left join dice
                    on rolls.remaining_dice[1] = dice.sides
            where len(rolls.remaining_dice) > 0
    )

    select
        n,
        array_to_string(combo, ','),
        outcome_id,
        combo,
        outcome,
    from rolls
    where len(outcome) = n
    order by all
;

/* roll_outcomes */
from roll_outcomes
;


/* Game scenarios */
create or replace table scenarios as
    select
        game.name,
        row_number() over () as scenario_id,
        attackers.combo as attackers,
        defenders.combo as defenders,
        attacker_wins_ties.enabled as attacker_wins_ties,
        plus_one_to_highest__attacker.enabled as plus_one_to_highest__attacker,
        plus_one_to_highest__defender.enabled as plus_one_to_highest__defender,
        plus_one_to_all__attacker.enabled as plus_one_to_all__attacker,
        plus_one_to_all__defender.enabled as plus_one_to_all__defender,
    from (values ('Risk: Game of Thrones Edition')) as game(name)
        left join dice_combinations as attackers on attackers.n <= 3
        left join dice_combinations as defenders on defenders.n <= 2
        cross join (values (false), (true)) as attacker_wins_ties(enabled)
        cross join (values (false), (true)) as plus_one_to_highest__attacker(enabled)
        cross join (values (false), (true)) as plus_one_to_highest__defender(enabled)
        cross join (values (false), (true)) as plus_one_to_all__attacker(enabled)
        cross join (values (false), (true)) as plus_one_to_all__defender(enabled)
;

/* scenarios */
from scenarios
;


/* Scenario outcomes */
create or replace table scenario_outcomes as
    with

    axis as (
        select
            scenarios.* exclude (name),
            generate_series as attacks_won
        from scenarios
            cross join generate_series(0, 2)
    ),

    scenario_outcomes as (
        select
            scenarios.scenario_id,

            coalesce(attacker_rolls.outcome[1], -99) as attacker_roll_1,
            coalesce(attacker_rolls.outcome[2], -99) as attacker_roll_2,
            coalesce(defender_rolls.outcome[1], -99) as defender_roll_1,
            coalesce(defender_rolls.outcome[2], -99) as defender_roll_2,

            (0
                + attacker_roll_1
                + scenarios.plus_one_to_highest__attacker::int
                + scenarios.plus_one_to_all__attacker::int
            ) as attacker_roll_1_modified,
            (0
                + attacker_roll_2
                + scenarios.plus_one_to_all__attacker::int
            ) as attacker_roll_2_modified,
            (0
                + defender_roll_1
                + scenarios.plus_one_to_highest__defender::int
                + scenarios.plus_one_to_all__defender::int
            ) as defender_roll_1_modified,
            (0
                + defender_roll_2
                + scenarios.plus_one_to_all__defender::int
            ) as defender_roll_2_modified,

            (0
                + (0=1
                    or attacker_roll_1_modified > defender_roll_1_modified
                    or (attacker_roll_1_modified = defender_roll_1_modified and scenarios.attacker_wins_ties)
                )::int
                + (1=1
                    and attacker_roll_2_modified > defender_roll_2_modified
                    and len(scenarios.defenders) = 2
                )::int
            ) as attacks_won
        from scenarios
            left join roll_outcomes as attacker_rolls
                on scenarios.attackers = attacker_rolls.combo
            left join roll_outcomes as defender_rolls
                on scenarios.defenders = defender_rolls.combo
    ),

    scenario_likelihoods as (
        select
            scenario_id,
            attacks_won,
            100.0 * count(*) / sum(count(*)) over (partition by scenario_id) as likelihood
        from scenario_outcomes
        group by
            scenario_id,
            attacks_won
    )

    select
        axis.*,
        coalesce(scenario_likelihoods.likelihood, 0)::numeric(6, 4) as likelihood
    from axis
        left join scenario_likelihoods
            using (scenario_id, attacks_won)
    order by all
;

/* scenario_outcomes */
from scenario_outcomes
;


/* Specific outcome */
select
    attacks_won,
    likelihood
from scenario_outcomes
where 1=1
    and attackers = [6, 8, 8]
    and defenders = [6, 8]
    and not attacker_wins_ties
    and not plus_one_to_highest__attacker
    and not plus_one_to_all__attacker
    and plus_one_to_highest__defender
    and plus_one_to_all__defender
;








------------------------------------------------------------------------
------------------------------------------------------------------------

/*
    Validation

    We can validate the likelihoods by comparing them to a simulation
    This is just for confidence in the numerical results.
*/


/* One fair 6-sided die: numerical (just to confirm this works) */
with rolls(roll) as (
    select 1 + floor(random() * 6)
    from generate_series(10_000_000)
)

select
    roll,
    count(*) as volume,
    (100.0 * count(*) / sum(count(*)) over ())::numeric(6, 4) as likelihood
from rolls
group by roll
order by roll
;


/* Three fair 6-sided dice: numerical vs simulation */
with

simulation_rolls as (
    select
        list_reverse_sort([roll_1, roll_2, roll_3]) as outcome,
        (100.0 * count(*) / sum(count(*)) over ())::numeric(6, 4) as likelihood
    from (
        select
            1 + floor(random() * 6) as roll_1,
            1 + floor(random() * 6) as roll_2,
            1 + floor(random() * 6) as roll_3,
        from generate_series(10_000_000)
    )
    group by outcome
    order by outcome
),

numerical_rolls as (
    select
        outcome,
        (100.0 * count(*) / sum(count(*)) over (partition by combo))::numeric(6, 4) as likelihood
    from roll_outcomes
    where combo = [6, 6, 6]
    group by combo, outcome
    order by all
)

select
    outcome,
    simulation_rolls.likelihood as simulation_likelihood,
    numerical_rolls.likelihood as numerical_likelihood,
    simulation_rolls.likelihood - numerical_rolls.likelihood as difference
from simulation_rolls
    full join numerical_rolls
        using (outcome)
;


/* Three fair 8-sided dice: numerical vs simulation */
with

simulation_rolls as (
    select
        list_reverse_sort([roll_1, roll_2, roll_3]) as outcome,
        (100.0 * count(*) / sum(count(*)) over ())::numeric(6, 4) as likelihood
    from (
        select
            1 + floor(random() * 8) as roll_1,
            1 + floor(random() * 8) as roll_2,
            1 + floor(random() * 8) as roll_3,
        from generate_series(10_000_000)
    )
    group by outcome
    order by outcome
),

numerical_rolls as (
    select
        outcome,
        (100.0 * count(*) / sum(count(*)) over (partition by combo))::numeric(6, 4) as likelihood
    from roll_outcomes
    where combo = [8, 8, 8]
    group by combo, outcome
    order by all
)

select
    outcome,
    simulation_rolls.likelihood as simulation_likelihood,
    numerical_rolls.likelihood as numerical_likelihood,
    simulation_rolls.likelihood - numerical_rolls.likelihood as difference
from simulation_rolls
    full join numerical_rolls
        using (outcome)
;
