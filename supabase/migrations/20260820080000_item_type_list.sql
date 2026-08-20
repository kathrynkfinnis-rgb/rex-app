-- #118's List-as-a-type-of-Rex rework creates the List itself as an `items`
-- row via createItem(type: "list", ...), exactly like a Trip does with
-- type: "trip" (see 20260730195538). That migration for "trip" landed, but
-- the equivalent for "list" never did — caught live in the simulator when
-- "Save as List" failed with:
--   {"code":"22P02","message":"invalid input value for enum item_type: \"list\""}
-- Same idempotent ADD VALUE pattern as every other type added after the
-- original ('place','book','movie','tv') enum.
ALTER TYPE public.item_type ADD VALUE IF NOT EXISTS 'list';
