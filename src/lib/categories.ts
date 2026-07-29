import { MapPin, Book, Film, Tv, ChefHat, Mic, Ticket, Sparkles } from "lucide-react";

export type ItemType = "place" | "book" | "movie" | "tv" | "recipe" | "podcast" | "event" | "other";

export const CATEGORIES: {
  type: ItemType;
  label: string;
  plural: string;
  icon: typeof MapPin;
  tokenClass: string;
  subtitleLabel: string;
  actionVerb: string;
  wantVerb: string;
  hitDefaultEmoji: string;
  hitDefaultLabel: string;
}[] = [
  { type: "place", label: "Place", plural: "Places", icon: MapPin, tokenClass: "bg-cat-place/15 text-cat-place", subtitleLabel: "Address or neighborhood", actionVerb: "Been here", wantVerb: "Want to visit", hitDefaultEmoji: "✈️", hitDefaultLabel: "To visit" },
  { type: "book", label: "Book", plural: "Books", icon: Book, tokenClass: "bg-cat-book/15 text-cat-book", subtitleLabel: "Author", actionVerb: "Read it", wantVerb: "Want to read", hitDefaultEmoji: "📚", hitDefaultLabel: "To be read" },
  { type: "movie", label: "Movie", plural: "Movies", icon: Film, tokenClass: "bg-cat-movie/15 text-cat-movie", subtitleLabel: "Year or director", actionVerb: "Seen it", wantVerb: "Want to watch", hitDefaultEmoji: "🎬", hitDefaultLabel: "To watch" },
  { type: "tv", label: "TV", plural: "TV shows", icon: Tv, tokenClass: "bg-cat-tv/15 text-cat-tv", subtitleLabel: "Network or year", actionVerb: "Watched it", wantVerb: "Want to watch", hitDefaultEmoji: "📺", hitDefaultLabel: "To watch" },
  { type: "podcast", label: "Podcast", plural: "Podcasts", icon: Mic, tokenClass: "bg-cat-podcast/15 text-cat-podcast", subtitleLabel: "Host or network", actionVerb: "Listened", wantVerb: "Want to listen", hitDefaultEmoji: "🎧", hitDefaultLabel: "To listen" },
  { type: "recipe", label: "Recipe", plural: "Recipes", icon: ChefHat, tokenClass: "bg-cat-recipe/15 text-cat-recipe", subtitleLabel: "Cookbook, chef, or source", actionVerb: "Cooked it", wantVerb: "Want to try", hitDefaultEmoji: "🍜", hitDefaultLabel: "To eat" },
  { type: "event", label: "Event", plural: "Events", icon: Ticket, tokenClass: "bg-cat-event/15 text-cat-event", subtitleLabel: "Venue, date, or type", actionVerb: "Went", wantVerb: "Want to go", hitDefaultEmoji: "🎟️", hitDefaultLabel: "To attend" },
  { type: "other", label: "Other", plural: "Other", icon: Sparkles, tokenClass: "bg-cat-other/15 text-cat-other", subtitleLabel: "What is it?", actionVerb: "Tried it", wantVerb: "Want to try", hitDefaultEmoji: "✨", hitDefaultLabel: "To try" },
];

export function categoryMeta(type: ItemType) {
  return CATEGORIES.find((c) => c.type === type)!;
}

export const PLACE_SUBCATEGORIES = [
  "Restaurant",
  "Private dining",
  "Bar",
  "Café",
  "Beauty",
  "Accommodation",
  "Shop",
  "Activity",
  "Other",
] as const;
export type PlaceSubcategory = (typeof PLACE_SUBCATEGORIES)[number];

export const SUBCATEGORIES: Record<ItemType, readonly string[]> = {
  place: PLACE_SUBCATEGORIES,
  recipe: [
    "Salad", "Soup", "Pasta", "Rice & grains", "Meat", "Fish & seafood",
    "Vegetarian", "Vegan", "Breakfast", "Dessert", "Baking", "Snack",
    "Drink", "Sauce & dressing", "Other",
  ],
  book: [
    "Fiction", "Non-fiction", "Thriller", "Mystery", "Sci-fi", "Fantasy",
    "Romance", "Biography", "History", "Business", "Self-help", "Poetry",
    "Kids", "Other",
  ],
  movie: [
    "Action", "Comedy", "Drama", "Thriller", "Horror", "Sci-fi",
    "Documentary", "Romance", "Animation", "Kids", "Other",
  ],
  tv: [
    "Drama", "Comedy", "Documentary", "Reality", "Crime", "Sci-fi",
    "Kids", "Sport", "Other",
  ],
  podcast: [
    "Comedy", "News", "History", "Business", "Interview", "True crime",
    "Society", "Sport", "Tech", "Other",
  ],
  event: [
    "Concert", "Exhibition", "Theatre", "Comedy", "Sport", "Talk",
    "Festival", "Film", "Other",
  ],
};

export function subcategoriesFor(type: ItemType | null | undefined): readonly string[] {
  if (!type) return [];
  return SUBCATEGORIES[type] ?? [];
}

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
