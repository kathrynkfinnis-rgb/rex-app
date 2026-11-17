package com.kathrynfinnis.rex.ui

/**
 * The category vocabulary, in one place.
 *
 * Nov 17 — lifted out of ItemDetailScreen, where it was private, because
 * Explore needs the same ten words and a third copy of them is how two screens
 * end up calling the same thing different names. The Tier enum next door moved
 * for the same reason on the same day.
 *
 * The names come from RexCategory in iOS Theme.swift, verbatim. "Movie" over
 * the British "Film" is a deliberate exception to the house rule on copy:
 * these ten words are the shared vocabulary of the category picker, the badges
 * and the search, and one of them differing by platform is a product
 * inconsistency rather than a localisation. If it changes it should change in
 * both places at once.
 *
 * An unknown type falls through to null rather than to the raw column value —
 * "other_thing" on screen is worse than nothing there.
 */
internal fun categoryLabel(type: String): String? = when (type) {
    "place" -> "Place"
    "trip" -> "Trip"
    "book" -> "Book"
    "movie" -> "Movie"
    "tv" -> "TV"
    "podcast" -> "Podcast"
    "recipe" -> "Recipe"
    "event" -> "Event"
    "other" -> "Other"
    "list" -> "List"
    else -> null
}

/**
 * The same names when they label a GROUP rather than one thing.
 *
 * From TestFlight on 27 August: "The titles of these categories (eg Book or
 * Place) should be pluralised (ie Books or Places)" — but only where the word
 * is naming a shelf or a filter ("show me Books"), never where it is naming
 * one item's type (a card badge, "Add a book"). TV, Other and List already
 * read correctly unpluralised, so they pass through unchanged.
 */
internal fun categoryPlural(type: String): String? = when (type) {
    "place" -> "Places"
    "trip" -> "Trips"
    "book" -> "Books"
    "movie" -> "Movies"
    "tv" -> "TV"
    "podcast" -> "Podcasts"
    "recipe" -> "Recipes"
    "event" -> "Events"
    "other" -> "Other"
    "list" -> "List"
    else -> null
}

/**
 * The order shelves appear in. Trips and lists are left out on purpose: both
 * are containers rather than things, iOS gives trips a shelf of their own, and
 * Android has no screen for either yet.
 */
internal val exploreCategories: List<String> =
    listOf("place", "book", "movie", "tv", "podcast", "recipe", "event", "other")
