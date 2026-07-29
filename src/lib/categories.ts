import { MapPin, Book, Film, Tv, ChefHat, Mic } from "lucide-react";

export type ItemType = "place" | "book" | "movie" | "tv" | "recipe" | "podcast";

export const CATEGORIES: {
  type: ItemType;
  label: string;
  plural: string;
  icon: typeof MapPin;
  tokenClass: string;
  subtitleLabel: string;
  actionVerb: string;
  wantVerb: string;
}[] = [
  { type: "place", label: "Place", plural: "Places", icon: MapPin, tokenClass: "bg-cat-place/15 text-cat-place", subtitleLabel: "Address or neighborhood", actionVerb: "Been here", wantVerb: "Want to visit" },
  { type: "book", label: "Book", plural: "Books", icon: Book, tokenClass: "bg-cat-book/15 text-cat-book", subtitleLabel: "Author", actionVerb: "Read it", wantVerb: "Want to read" },
  { type: "movie", label: "Movie", plural: "Movies", icon: Film, tokenClass: "bg-cat-movie/15 text-cat-movie", subtitleLabel: "Year or director", actionVerb: "Seen it", wantVerb: "Want to watch" },
  { type: "tv", label: "TV", plural: "TV shows", icon: Tv, tokenClass: "bg-cat-tv/15 text-cat-tv", subtitleLabel: "Network or year", actionVerb: "Watched it", wantVerb: "Want to watch" },
  { type: "podcast", label: "Podcast", plural: "Podcasts", icon: Mic, tokenClass: "bg-cat-podcast/15 text-cat-podcast", subtitleLabel: "Host or network", actionVerb: "Listened", wantVerb: "Want to listen" },
  { type: "recipe", label: "Recipe", plural: "Recipes", icon: ChefHat, tokenClass: "bg-cat-recipe/15 text-cat-recipe", subtitleLabel: "Cookbook, chef, or source", actionVerb: "Cooked it", wantVerb: "Want to try" },
];

export function categoryMeta(type: ItemType) {
  return CATEGORIES.find((c) => c.type === type)!;
}

export const PLACE_SUBCATEGORIES = [
  "Restaurant",
  "Bar",
  "Café",
  "Beauty",
  "Accommodation",
  "Shop",
  "Activity",
  "Other",
] as const;
export type PlaceSubcategory = (typeof PLACE_SUBCATEGORIES)[number];

// Map Google Places primaryTypeDisplayName (or free text) to our subcategory.
export function normalizePlaceSubcategory(input: string | null | undefined): PlaceSubcategory | null {
  if (!input) return null;
  const s = input.toLowerCase();
  if (/(bar|pub|brewery|wine|cocktail|nightclub)/.test(s)) return "Bar";
  if (/(caf[eé]|coffee|tea|bakery|patisserie)/.test(s)) return "Café";
  if (/(restaurant|food|eatery|bistro|diner|steakhouse|pizzeria|ramen|sushi|kitchen)/.test(s)) return "Restaurant";
  if (/(salon|spa|barber|beauty|nail|hair|massage)/.test(s)) return "Beauty";
  if (/(hotel|hostel|inn|resort|motel|lodging|bed|guest house|guesthouse)/.test(s)) return "Accommodation";
  if (/(shop|store|boutique|market|mall)/.test(s)) return "Shop";
  if (/(gym|park|museum|gallery|cinema|theater|theatre|club|stadium|attraction)/.test(s)) return "Activity";
  return "Other";
}
