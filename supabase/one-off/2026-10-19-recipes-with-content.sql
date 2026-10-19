-- Oct 19 — "pls delete the empty recipes, and then queue them again with
-- content", and then: "is there an easier way to do it in supabase?"
--
-- There is, and it is also a better outcome than deleting.
--
-- The six posts are not themselves broken. What is empty is the `items` row
-- behind each one: the app reads a recipe's ingredients and method out of
-- items.recipe_text and renders nothing at all when it is null. So this
-- fills those in and sets published_at back to null, which puts the same six
-- posts into the REX admin queue to be read and posted deliberately.
--
-- Same end state as delete-and-re-queue, except nothing is destroyed: any
-- likes or comments testers left on them survive, and no secret key is
-- needed because it is all one statement in the SQL editor.
--
-- The recipes are written in our own words. The two that name a cook name
-- them in the title; attribution is not permission to reprint their prose,
-- so these are the quantities the dish needs and short functional steps.
--
-- Format matters: RexRecipe.parse wants "## Ingredients" and "## Method"
-- headings with hyphen bullets and numbered steps. Anything else still
-- shows, but as one undivided block instead of two sections.

begin;

update public.items set recipe_text = $rex$## Ingredients
- 400g frozen dumplings, any filling
- 400ml tin of coconut milk
- 2 tbsp red curry paste
- 1 tbsp fresh ginger, grated
- 2 cloves of garlic, grated
- 1 tbsp soy sauce
- 1 tsp caster sugar
- 2 tbsp chilli crunch, and more to serve
- Coriander and a lime, to serve

## Method
1. Heat the oven to 200C fan.
2. Whisk the coconut milk, curry paste, ginger, garlic, soy and sugar together in a roasting tin until smooth.
3. Add the dumplings straight from the freezer and turn them over in the sauce, in a single layer.
4. Bake for 25 minutes, until the sauce has thickened at the edges and the dumplings are soft through.
5. Spoon over the chilli crunch, scatter with coriander, and serve with the lime cut into wedges.$rex$
where type = 'recipe' and title = 'One-pan dumpling and coconut curry bake';

update public.items set recipe_text = $rex$## Ingredients
- 250ml whole milk
- 2 tsp caster sugar
- 1/2 tsp vanilla extract, or half a split pod
- A pinch of salt

## Method
1. Warm the milk gently in a small pan until it steams, without letting it boil.
2. Stir in the sugar, vanilla and salt until the sugar has completely dissolved.
3. Pour into a mug and drink it warm.$rex$
where type = 'recipe' and title = 'Angel milk';

update public.items set recipe_text = $rex$## Ingredients
- 300g pasta
- 2 chicken breasts, sliced thin
- 8 cloves of garlic, finely sliced
- 30g butter
- 1 tbsp olive oil
- 200ml double cream
- 60g parmesan, finely grated, and more to serve
- Parsley, salt and black pepper

## Method
1. Cook the pasta in well-salted water, and keep a mugful of the water back before draining.
2. Meanwhile, season the chicken and fry it in the oil over a high heat until browned. Set it aside.
3. Lower the heat, melt the butter in the same pan and cook the garlic gently for two minutes without letting it colour.
4. Pour in the cream, bring it to a simmer, then stir in the parmesan until smooth.
5. Return the chicken, add the pasta, and loosen it with the reserved water until the sauce coats everything.
6. Finish with parsley, plenty of pepper and more parmesan.$rex$
where type = 'recipe' and title = 'Creamy garlic parmesan chicken pasta';

update public.items set recipe_text = $rex$## Ingredients
- 2 thick slices of sourdough
- 150g cream cheese or ricotta
- 1 tbsp olive oil
- A squeeze of lemon
- Hot honey, to drizzle
- A handful of toasted nuts or seeds
- Chilli flakes, flaky salt and black pepper

## Method
1. Toast the bread until it is properly crisp — it has to hold the weight.
2. Whip the cheese with the olive oil, lemon and a pinch of salt until light.
3. Spread it thickly, right to the edges.
4. Pile on the nuts, drizzle with hot honey, and finish with chilli flakes, salt and pepper.$rex$
where type = 'recipe' and title = 'Loaded fortress toast';

update public.items set recipe_text = $rex$## Ingredients
- 800g tinned whole plum tomatoes
- 5 tbsp butter
- 1 onion, peeled and halved
- Salt

## Method
1. Put the tomatoes, butter and both onion halves in a pan with a good pinch of salt.
2. Simmer uncovered over a low heat for about 45 minutes, stirring now and then and crushing the tomatoes against the side of the pan.
3. Lift out the onion, taste, and season. Enough for 500g of pasta.$rex$
where type = 'recipe' and title = 'Marcella Hazan''s tomato sauce';

update public.items set recipe_text = $rex$## Ingredients
- 1 chicken, jointed, or 8 thighs and drumsticks
- 4 clementines — 3 sliced into rounds, 1 juiced
- 1 fennel bulb, sliced
- 100ml arak, ouzo or pernod
- 4 tbsp olive oil
- 3 tbsp orange juice
- 2 tbsp lemon juice
- 1 tbsp grainy mustard
- 2 tbsp soft brown sugar
- 2 tsp fennel seeds, lightly crushed
- Thyme, salt and black pepper

## Method
1. Whisk the arak, oil, citrus juices, mustard, sugar and fennel seeds into a marinade and season it well.
2. Turn the chicken, fennel and clementine slices through it, and leave in the fridge for a few hours or overnight.
3. Heat the oven to 220C fan. Spread everything out in one tray, skin side up, and pour the marinade around it.
4. Roast for 35 to 45 minutes, until the skin is deeply browned and the clementines have caught at the edges.
5. Rest for five minutes, then spoon the tray juices over to serve.$rex$
where type = 'recipe' and title = 'Ottolenghi''s roast chicken with clementines';

-- Back into the queue. Only REX's own recipe posts, and only the six above:
-- joining on items means a recipe somebody else wrote is never touched, and
-- requiring recipe_text to be present now means this cannot pull anything
-- back out of the feed that it did not just fill in.
update public.recommendations r
   set published_at = null
  from public.items i
 where i.id = r.item_id
   and r.user_id = (select id from public.profiles where is_official limit 1)
   and i.type = 'recipe'
   and nullif(btrim(i.recipe_text), '') is not null;

-- What you should see: six rows, each with its recipe, all unpublished.
select i.title,
       length(i.recipe_text) as recipe_length,
       r.published_at
  from public.recommendations r
  join public.items i on i.id = r.item_id
 where r.user_id = (select id from public.profiles where is_official limit 1)
   and i.type = 'recipe'
 order by i.title;

commit;
