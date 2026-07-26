import { MapPin, Book, Film, Tv } from "lucide-react";

export type ItemType = "place" | "book" | "movie" | "tv";

export const CATEGORIES: {
  type: ItemType;
  label: string;
  plural: string;
  icon: typeof MapPin;
  tokenClass: string;
  subtitleLabel: string;
  actionVerb: string;
}[] = [
  { type: "place", label: "Place", plural: "Places", icon: MapPin, tokenClass: "bg-cat-place/15 text-cat-place", subtitleLabel: "Address or neighborhood", actionVerb: "Been here" },
  { type: "book", label: "Book", plural: "Books", icon: Book, tokenClass: "bg-cat-book/15 text-cat-book", subtitleLabel: "Author", actionVerb: "Read it" },
  { type: "movie", label: "Movie", plural: "Movies", icon: Film, tokenClass: "bg-cat-movie/15 text-cat-movie", subtitleLabel: "Year or director", actionVerb: "Seen it" },
  { type: "tv", label: "TV", plural: "TV shows", icon: Tv, tokenClass: "bg-cat-tv/15 text-cat-tv", subtitleLabel: "Network or year", actionVerb: "Watched it" },
];

export function categoryMeta(type: ItemType) {
  return CATEGORIES.find((c) => c.type === type)!;
}
