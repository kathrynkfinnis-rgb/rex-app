-- Oct 5 — "let's do option three, but we need to build in safeguards to
-- ensure that places with the same name don't get Rex'd by mistake (e.g. all
-- the pubs called the Crown)."
--
-- Option three: nobody Rexes a place they haven't been to. Instead a place
-- knows its siblings, so the map can show an un-Rex'd branch as a hollow pin
-- and the item page can count across the chain. Every Rex stays first-hand.
--
-- chain_key is what makes two places siblings. It is the brand's own web
-- domain — bancone.co.uk — and that choice is the safeguard. Checked against
-- what Google actually returns today:
--
--   Bancone's five London branches   all bancone.co.uk          one chain
--   "The Crown", eight results       seven different domains     no chain
--                                    (greeneking, vintageinn,
--                                     nicholsonspubs, …)
--   Relais de l'Entrecôte            the real two share a domain;
--                                    Relais de Venise and
--                                    L'Entrecôte de Paris don't
--
-- A name can't tell those apart and never will. A shared domain can, because
-- a chain is a business and a business has one website, while thirty pubs
-- called the Crown have thirty landlords.
--
-- Two further guards live in the app (see RexSearch.chainKey):
--   * the domain must look like the place's own brand, so a pub group's
--     booking site doesn't bind unrelated pubs into a "chain";
--   * a chain needs at least two places sharing the domain, so a single pub
--     with its own website is not a chain of one.
alter table public.items
  add column if not exists chain_key text;

create index if not exists items_chain_key_idx
  on public.items(chain_key) where chain_key is not null;

comment on column public.items.chain_key is
  'The brand domain shared by branches of one chain, e.g. bancone.co.uk. Null for anywhere that is not part of one. Set from the place''s own website, never from its name — see the migration note.';
