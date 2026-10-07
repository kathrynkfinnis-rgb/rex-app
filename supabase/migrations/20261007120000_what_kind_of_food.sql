-- Oct 7 — "for restaurants, please can we have a sub-sub-category filter…
-- they should be types of food… for old pins, will need to run a
-- recategorisation?"
--
-- Yes, and this is it. The cuisine needs no new column: items.genre has always
-- been a comma-separated list, which is also how "things can belong to two
-- sub-sub-categories" works — "Restaurant, Italian, Spanish" is already legal.
--
-- Almost nothing has to be retagged by hand, because Google's
-- primaryTypeDisplayName leads with the cuisine and we have been storing it:
-- "Caribbean restaurant", "Cantonese restaurant", "Taco Restaurant", "Japanese
-- restaurant". The app used to collapse that away into the shape, because one
-- chip per cuisine is unfilterable; this reads it back out.
--
-- Conservative in the same way rexNormalisedGenres is: a term that isn't
-- clearly one of the thirteen is left alone. Korean, Caribbean and Ethiopian
-- places stay untagged rather than being forced into a neighbouring box — an
-- untagged restaurant is a small loss, one filed under the wrong cuisine is a
-- wrong answer that looks right.
--
-- Two guards are load-bearing and both are about a word meaning two things:
--   * "Latin American" is not American, and Google uses the phrase.
--   * "Southern Italian" would match a 'southern' → American rule, so there
--     is no such rule; American is reached by its own name and by burger,
--     steakhouse, barbecue, diner and new american.
--
-- Running it twice is safe: a cuisine already present as its own comma piece
-- is never appended again.

with cuisine_order(cuisine, pos) as (
  values ('Italian',1), ('Japanese',2), ('Mexican',3), ('Thai',4),
         ('Vietnamese',5), ('Chinese',6), ('Indian',7), ('Mediterranean',8),
         ('Middle Eastern',9), ('French',10), ('American',11), ('Spanish',12),
         ('British',13)
),
mapping(needle, cuisine) as (
  values
    -- Each cuisine answers to its own name as well as to these.
    ('italian','Italian'), ('pizza','Italian'), ('pizzeria','Italian'),
    ('trattoria','Italian'), ('osteria','Italian'), ('pasta','Italian'),
    ('sicilian','Italian'), ('neapolitan','Italian'), ('tuscan','Italian'),

    ('japanese','Japanese'), ('sushi','Japanese'), ('ramen','Japanese'),
    ('izakaya','Japanese'), ('yakitori','Japanese'), ('teppanyaki','Japanese'),

    ('mexican','Mexican'), ('taco','Mexican'), ('tacos','Mexican'),
    ('taqueria','Mexican'), ('burrito','Mexican'), ('tex mex','Mexican'),

    ('thai','Thai'),

    ('vietnamese','Vietnamese'), ('pho','Vietnamese'), ('banh mi','Vietnamese'),

    ('chinese','Chinese'), ('cantonese','Chinese'), ('szechuan','Chinese'),
    ('sichuan','Chinese'), ('hunan','Chinese'), ('dim sum','Chinese'),
    ('dumpling','Chinese'), ('shanghainese','Chinese'), ('taiwanese','Chinese'),

    ('indian','Indian'), ('curry','Indian'), ('punjabi','Indian'),
    ('tandoori','Indian'), ('balti','Indian'),

    ('mediterranean','Mediterranean'), ('greek','Mediterranean'),
    ('cypriot','Mediterranean'), ('sardinian','Mediterranean'),

    ('middle eastern','Middle Eastern'), ('lebanese','Middle Eastern'),
    ('persian','Middle Eastern'), ('iranian','Middle Eastern'),
    ('turkish','Middle Eastern'), ('israeli','Middle Eastern'),
    ('falafel','Middle Eastern'), ('shawarma','Middle Eastern'),
    ('mezze','Middle Eastern'),

    ('french','French'), ('bistro','French'), ('brasserie','French'),
    ('patisserie','French'), ('creperie','French'),

    ('american','American'), ('burger','American'), ('hamburger','American'),
    ('steakhouse','American'), ('barbecue','American'), ('bbq','American'),
    ('diner','American'), ('soul food','American'), ('new american','American'),

    ('spanish','Spanish'), ('tapas','Spanish'), ('basque','Spanish'),
    ('catalan','Spanish'), ('paella','Spanish'),

    ('british','British'), ('fish and chips','British'),
    ('fish & chips','British'), ('sunday roast','British'),
    ('modern british','British'), ('english','British'),
    ('scottish','British'), ('welsh','British')
),
matched as (
  select distinct i.id, m.cuisine
  from public.items i
  join mapping m
    -- Whole words, so 'american' matches "New American Restaurant" and not
    -- some longer word that happens to contain it.
    on i.genre ~* ('(^|[^[:alnum:]])' || m.needle || '([^[:alnum:]]|$)')
  where i.type::text = 'place'
    and coalesce(i.genre, '') <> ''
    -- See the note above: Google says "Latin American", which is not this.
    and not (m.cuisine = 'American' and i.genre ~* 'latin')
    -- Already tagged, so leave it be — this is what makes a re-run harmless.
    and not exists (
      select 1 from unnest(string_to_array(i.genre, ',')) part
      where btrim(lower(part)) = lower(m.cuisine)
    )
),
ranked as (
  select m.id, m.cuisine,
         row_number() over (partition by m.id order by o.pos) as rn
  from matched m
  join cuisine_order o on o.cuisine = m.cuisine
),
chosen as (
  -- Two is the most anywhere honestly is; past that the tags stop meaning
  -- anything and the card has nowhere to put them.
  select id, string_agg(cuisine, ', ' order by rn) as cuisines
  from ranked
  where rn <= 2
  group by id
)
update public.items i
set genre = btrim(i.genre, ' ,') || ', ' || c.cuisines
from chosen c
where c.id = i.id;
