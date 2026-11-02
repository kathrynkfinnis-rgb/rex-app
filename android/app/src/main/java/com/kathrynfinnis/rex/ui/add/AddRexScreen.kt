package com.kathrynfinnis.rex.ui.add

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.MenuBook
import androidx.compose.material.icons.outlined.AutoAwesome
import androidx.compose.material.icons.outlined.Mic
import androidx.compose.material.icons.outlined.Movie
import androidx.compose.material.icons.outlined.Place
import androidx.compose.material.icons.outlined.Restaurant
import androidx.compose.material.icons.outlined.Tv
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kathrynfinnis.rex.data.Rex
import com.kathrynfinnis.rex.data.RexAuth
import com.kathrynfinnis.rex.ui.theme.RexColor
import kotlinx.coroutines.launch

/**
 * Adding a Rex by hand.
 *
 * The subset of AddRexView.swift that works without catalogue search: this
 * build has no Google Places, no TMDB and no iTunes lookup, so every field is
 * typed. iOS calls this same path "Enter details manually" and has offered it
 * since the web app did — it is a real route somebody uses when the catalogue
 * has never heard of the place, not a stub standing in for search.
 *
 * Three things are deliberately shaped differently from iOS, each noted at the
 * point it happens: the category picker is inline rather than a first step,
 * "I've done it / want to try" is absent, and nothing is pre-selected on the
 * rating beyond the neutral tier.
 */
@Composable
fun AddRexScreen(onSaved: () -> Unit, onCancel: () -> Unit) {
    // Resolving is its own state, not "signed out until proved otherwise".
    // RexAuth.isResolving exists because the SDK reads a stored session off
    // disk on launch; treating that moment as signed out would show somebody
    // already signed in a "you need an account" panel for a frame.
    val resolving by RexAuth.isResolving.collectAsState(initial = true)
    val signedIn by RexAuth.isSignedIn.collectAsState(initial = false)

    when {
        resolving -> Notice(
            heading = "One moment",
            body = "Checking you're still signed in.",
            onCancel = onCancel,
            busy = true,
        )

        // Rex.createRecommendation throws "Not signed in." without a session,
        // and RLS would refuse the insert regardless. Saying so before the
        // form is filled in is kinder than letting somebody write a note
        // about a restaurant and then losing it to an error.
        !signedIn -> Notice(
            heading = "Sign in to add a Rex",
            body = "A Rex is posted as you, so it needs an account. Sign in and " +
                "come back — nothing you've typed here is saved yet.",
            onCancel = onCancel,
        )

        else -> AddRexForm(onSaved = onSaved, onCancel = onCancel)
    }
}

// ─────────────────────────────────────────────────────────── the categories

/**
 * The seven categories this build can add. Trips, lists and events are the
 * three iOS has and this does not: a trip needs the stops builder, a list is a
 * container rather than a thing you rate, and an event's useful fields are its
 * venue and date, which is a form of its own rather than a label change.
 *
 * `type` is the string the items table stores, and it matches RexCategory's
 * raw value in Theme.swift exactly — the database is the contract, and a Rex
 * added on Android that reads as a different category on iOS is the Oct 3 bug
 * ("this is a podcast, not a place") arriving by a new route.
 */
private enum class Category(
    val type: String,
    val label: String,
    val icon: ImageVector,
) {
    Place("place", "Place", Icons.Outlined.Place),
    Book("book", "Book", Icons.AutoMirrored.Outlined.MenuBook),
    Movie("movie", "Movie", Icons.Outlined.Movie),
    Tv("tv", "TV", Icons.Outlined.Tv),
    Podcast("podcast", "Podcast", Icons.Outlined.Mic),
    Recipe("recipe", "Recipe", Icons.Outlined.Restaurant),
    Other("other", "Other", Icons.Outlined.AutoAwesome);

    /**
     * Ported from RexCategory.withArticle. Oct 9 — "this should read add an
     * other": the heading used to be "Add a " plus the lowercased label, which
     * gives "Add a other". TV is the case a vowel test gets wrong on its own —
     * the letter is a consonant, the way it is said is not — so it is named
     * outright.
     */
    val withArticle: String
        get() {
            if (this == Tv) return "a TV show"
            val name = label.lowercase()
            val article = if (name.first() in "aeiou") "an" else "a"
            return "$article $name"
        }

    /**
     * The second, optional field. Every label is something answerable, which
     * is the whole point of varying it — Oct 3 on iOS, "I thought we had
     * removed subtitle from Adds?", was about a place showing the literal word
     * "Subtitle" above a box nobody could guess the contents of.
     *
     * A place gets Address rather than a subtitle, and it is saved to the
     * address column rather than the subtitle one. This differs from the
     * brief, which asked for a subtitle on every category, and the reason is
     * deduplication: Rex.findOrCreateItem skips its title+subtitle match
     * entirely for places, so a place's subtitle does no work at all, whereas
     * an address is what iOS matches places on and what the map will need.
     */
    val secondaryLabel: String
        get() = when (this) {
            Place -> "Address"
            Book -> "Author"
            Movie, Tv -> "Year or director"
            Podcast -> "Host or network"
            Recipe -> "Cookbook, chef, or source"
            Other -> "Subtitle"
        }

    /**
     * How to refer to one of these in a sentence. Not `label.lowercase()`:
     * that gives "the same tv" and "the same other", which is the same class
     * of mistake as the Oct 9 "Add a other".
     */
    val noun: String
        get() = when (this) {
            Tv -> "TV show"
            Other -> "thing"
            else -> label.lowercase()
        }

    /** Copied from placeholderTitle(for:) so the two apps prompt alike. */
    val titleExample: String
        get() = when (this) {
            Place -> "Dishoom"
            Book -> "The Hobbit"
            Movie -> "Inception"
            Tv -> "Breaking Bad"
            Podcast -> "This American Life"
            Recipe -> "Koshari"
            Other -> "Title"
        }
}

/**
 * The five tiers, with the value each one saves.
 *
 * `rating` is copied from RexRatingTier.representativeRawValue in
 * RexRatingScale.swift rather than re-derived as a band midpoint. The two
 * platforms write into one column that other rows have been using since the
 * old 1-10 crowns, and FeedRecommendation.tier buckets it back on read. If
 * Android saved 6.5 for Meh and iOS saved 6, the same tier would be two
 * numbers in the database and any future averaging would drift between them.
 *
 * Checked against FeedRecommendation.tier: 3 -> Do not Rex, 6 -> Meh,
 * 8 -> Rex, 9 -> Loved, 10 -> Obsessed. Each value buckets back to its own
 * tier, which is the property that has to hold.
 */
private enum class Tier(val label: String, val emoji: String, val rating: Double) {
    // The glyph names are spelled out because an emoji is the one thing in
    // this file a code review in a terminal cannot read back to you.
    DoNotRex("Do not Rex", "⛔️", 3.0), // no entry
    Meh("Meh", "🤷‍♂️", 6.0), // man shrugging
    Rex("Rex", "👌", 8.0), // OK hand
    Loved("Loved", "♥️", 9.0), // heart
    Obsessed("Obsessed", "💯", 10.0), // hundred points
}

// ─────────────────────────────────────────────────────────────── the screen

private sealed interface Save {
    data object Idle : Save
    data object Posting : Save
    data class Failed(val message: String) : Save
}

@Composable
private fun AddRexForm(onSaved: () -> Unit, onCancel: () -> Unit) {
    val scope = rememberCoroutineScope()

    var category by remember { mutableStateOf(Category.Place) }
    var title by remember { mutableStateOf("") }
    var secondary by remember { mutableStateOf("") }
    var note by remember { mutableStateOf("") }
    // Pre-selected, and deliberately at Rex rather than at the top of the
    // scale. iOS opens on 10, which posts "Obsessed" for anyone who does not
    // look at the row; nothing pre-selected instead means a save blocked on a
    // field the brief does not block on, or a Rex written at rating 0, which
    // FeedRecommendation.tier renders as no opinion at all — the Sept 15 bug
    // where unrated imports read as "Do not Rex". Rex (8) is what iOS itself
    // resets a cleared draft to, so it is their neutral too.
    var tier by remember { mutableStateOf(Tier.Rex) }
    var save by remember { mutableStateOf<Save>(Save.Idle) }

    val posting = save is Save.Posting
    val canPost = !posting && title.isNotBlank()

    Column(
        Modifier
            .fillMaxSize()
            .imePadding()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
    ) {
        Row(
            Modifier.fillMaxWidth().padding(top = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "Add ${category.withArticle}",
                fontSize = 22.sp,
                fontWeight = FontWeight.SemiBold,
                color = RexColor.foreground,
                modifier = Modifier.weight(1f),
            )
            // Enabled mid-flight on purpose: the insert cannot be recalled,
            // but somebody who has changed their mind should not be trapped
            // watching a spinner. Whoever wires navigation decides what
            // cancelling during a post means for the back stack.
            TextButton(onClick = onCancel) {
                Text("Cancel", color = RexColor.mutedForeground)
            }
        }

        Spacer(Modifier.height(4.dp))
        Label("What is it?")

        // iOS makes the category a first step and the form a second one. Kept
        // inline here because navigation in this build is wired by hand
        // afterwards, and a two-screen flow would need a route of its own that
        // nobody has agreed to yet. It also means changing your mind about the
        // category does not throw away what you have typed, which on iOS it
        // does.
        //
        // Fixed rows of four rather than FlowRow: seven chips land as 4 + 3 at
        // every width this screen is used at, and an experimental layout API
        // is not worth taking on for a result that is already known.
        Category.entries.chunked(4).forEach { row ->
            Row(
                Modifier.fillMaxWidth().padding(top = 8.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                row.forEach { option ->
                    CategoryChip(
                        category = option,
                        selected = option == category,
                        enabled = !posting,
                        onClick = { category = option },
                        modifier = Modifier.weight(1f),
                    )
                }
                // Keeps the last row's chips the same width as the first's
                // instead of stretching three across four columns.
                repeat(4 - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }

        Spacer(Modifier.height(20.dp))
        Label("Title")
        Field(
            value = title,
            onValueChange = { title = it },
            placeholder = "e.g. ${category.titleExample}",
            enabled = !posting,
        )

        Spacer(Modifier.height(14.dp))
        Label(category.secondaryLabel)
        Field(
            value = secondary,
            onValueChange = { secondary = it },
            placeholder = "Optional",
            enabled = !posting,
        )
        if (category != Category.Place) {
            // Worth saying plainly: Rex.findOrCreateItem only merges a new
            // item with one already in the catalogue when both have a
            // subtitle, case-blind — the Nov 1 "still double rexing" fix. An
            // empty subtitle is not a failure, but it does mean a second copy
            // of the item, and somebody filling in the form has no other way
            // to know that.
            Spacer(Modifier.height(6.dp))
            Text(
                "Worth filling in — it's how we spot you mean the same " +
                    "${category.noun} somebody else has already Rexed.",
                fontSize = 11.sp,
                color = RexColor.mutedForeground,
            )
        }

        Spacer(Modifier.height(20.dp))
        Label("Your rating")
        Spacer(Modifier.height(8.dp))
        // Five tiers, not a number. The column stores 1-10 and always has, but
        // nobody has picked a number since the crowns were replaced — see
        // RexRatingScale.swift. Non-clearable, matching the add form on iOS:
        // clearing back to unrated is for the item page's take editor, where
        // there is something to clear.
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            Tier.entries.forEach { option ->
                TierChip(
                    tier = option,
                    selected = option == tier,
                    enabled = !posting,
                    onClick = { tier = option },
                    modifier = Modifier.weight(1f),
                )
            }
        }

        Spacer(Modifier.height(20.dp))
        Label("Note")
        Field(
            value = note,
            onValueChange = { note = it },
            // iOS's own prompt. It leads the right way for four of the five
            // tiers and reads oddly under Do not Rex, which is true on iOS
            // too; varying it by tier would be a change to copy nobody has
            // asked for.
            placeholder = "What did you love about it?",
            enabled = !posting,
            minLines = 3,
        )

        (save as? Save.Failed)?.let {
            Spacer(Modifier.height(14.dp))
            Text(it.message, color = RexColor.destructive, fontSize = 13.sp)
        }

        Spacer(Modifier.height(20.dp))
        Button(
            onClick = {
                save = Save.Posting
                scope.launch {
                    // The failure message, or null for success. Worked out
                    // before anything is reported so that onSaved() sits
                    // outside the catch — a navigation callback that throws
                    // would otherwise be shown as "your Rex didn't save"
                    // after it already had.
                    val failure: String? = try {
                        // findOrCreateItem does the deduplication, including
                        // the case-blind title match and the external-id one.
                        // Looking for an existing item here would be a second,
                        // worse copy of rules RexApi.kt documents at length.
                        val itemId = Rex.findOrCreateItem(
                            type = category.type,
                            title = title.trim(),
                            // A place's second field is its address; see
                            // Category.secondaryLabel.
                            subtitle = if (category == Category.Place) null
                            else secondary.trim().ifEmpty { null },
                            address = if (category == Category.Place) secondary.trim().ifEmpty { null }
                            else null,
                        )
                        Rex.createRecommendation(
                            itemId = itemId,
                            rating = tier.rating,
                            note = note.ifBlank { null },
                        )
                        null
                    } catch (e: Exception) {
                        // Two distinguishable failures, because the useful
                        // next step is different for each. Everything else
                        // carries the underlying message: it is usually the
                        // network or a PostgREST complaint, and hiding it
                        // behind "something went wrong" leaves nobody —
                        // including us, reading a screenshot — any wiser.
                        if (e.message?.contains("Not signed in", true) == true) {
                            "Your session ran out before this saved. Sign in " +
                                "again and your Rex will post."
                        } else {
                            "That didn't save, so nothing has been posted. " +
                                "Check your connection and try again. " +
                                "(${e.message ?: e::class.simpleName})"
                        }
                    }

                    if (failure == null) {
                        save = Save.Idle
                        onSaved()
                    } else {
                        save = Save.Failed(failure)
                    }
                }
            },
            enabled = canPost,
            shape = RoundedCornerShape(14.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = RexColor.primary,
                contentColor = RexColor.primaryForeground,
                disabledContainerColor = RexColor.disabled,
                disabledContentColor = RexColor.primaryForeground,
            ),
            modifier = Modifier.fillMaxWidth().height(52.dp),
        ) {
            if (posting) {
                CircularProgressIndicator(
                    color = RexColor.primaryForeground,
                    strokeWidth = 2.dp,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.size(10.dp))
            }
            // "Post", as on iOS. A Rex goes to your friends' feeds, and "Save"
            // would read as filing it away privately.
            Text(if (posting) "Posting…" else "Post", fontWeight = FontWeight.SemiBold)
        }

        if (title.isBlank() && !posting) {
            Spacer(Modifier.height(8.dp))
            Text(
                "Add a title and you can post this.",
                fontSize = 12.sp,
                color = RexColor.mutedForeground,
            )
        }

        Spacer(Modifier.height(32.dp))
    }
}

// ───────────────────────────────────────────────────────────────── the parts

@Composable
private fun Label(text: String) {
    Text(text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = RexColor.foreground)
}

@Composable
private fun Field(
    value: String,
    onValueChange: (String) -> Unit,
    placeholder: String,
    enabled: Boolean,
    minLines: Int = 1,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        enabled = enabled,
        placeholder = { Text(placeholder, color = RexColor.placeholder) },
        singleLine = minLines == 1,
        minLines = minLines,
        maxLines = if (minLines == 1) 1 else 8,
        shape = RoundedCornerShape(14.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedTextColor = RexColor.foreground,
            unfocusedTextColor = RexColor.foreground,
            disabledTextColor = RexColor.mutedForeground,
            focusedContainerColor = RexColor.card,
            unfocusedContainerColor = RexColor.card,
            disabledContainerColor = RexColor.card,
            cursorColor = RexColor.primary,
            focusedBorderColor = RexColor.primary,
            unfocusedBorderColor = RexColor.border,
            disabledBorderColor = RexColor.border,
        ),
        modifier = Modifier.fillMaxWidth(),
    )
}

/**
 * Icon above label, tinted to the brand rather than one colour per category.
 * iOS gives each category its own accent (RexCategory.colour), which is worth
 * having — but those hex values live in Theme.swift and are not in the Android
 * RexColor yet, and inventing seven approximations here is exactly the drift
 * Theme.kt's own header warns about.
 */
@Composable
private fun CategoryChip(
    category: Category,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val content = when {
        selected -> RexColor.primaryForeground
        enabled -> RexColor.mutedForeground
        else -> RexColor.disabled
    }
    Column(
        modifier
            .clip(RoundedCornerShape(14.dp))
            .selectableSurface(selected = selected, enabled = enabled, onClick = onClick)
            .padding(vertical = 10.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Icon(
            category.icon,
            contentDescription = null,
            tint = content,
            modifier = Modifier.size(20.dp),
        )
        Spacer(Modifier.height(4.dp))
        Text(
            category.label,
            fontSize = 11.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = content,
            textAlign = TextAlign.Center,
            maxLines = 1,
        )
    }
}

/** RexRatingPicker's tile, as close as Compose gets to the SwiftUI one. */
@Composable
private fun TierChip(
    tier: Tier,
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    Column(
        modifier
            .clip(RoundedCornerShape(14.dp))
            .selectableSurface(selected = selected, enabled = enabled, onClick = onClick)
            .padding(vertical = 10.dp, horizontal = 2.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Sept 14 on iOS — the emoji wins over a word or a percentage
        // wherever the device can draw it, which is Kathryn's call and holds
        // on Android for the same reason.
        Text(tier.emoji, fontSize = 18.sp)
        Spacer(Modifier.height(4.dp))
        Text(
            tier.label,
            fontSize = 10.sp,
            fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
            color = when {
                selected -> RexColor.primaryForeground
                enabled -> RexColor.mutedForeground
                else -> RexColor.disabled
            },
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
    }
}

/**
 * The shared chip surface: filled when chosen, card with a hairline when not,
 * and the border stays on in both states so a chip does not change size as it
 * is selected. One helper because the category row and the rating row are the
 * same control with different contents, and two copies of it is how they end
 * up a pixel apart.
 */
private fun Modifier.selectableSurface(
    selected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
): Modifier = this
    // No shape on the background: the caller clips first, so the fill already
    // follows the corners and naming the radius twice is how the two drift.
    .background(if (selected) RexColor.primary else RexColor.card)
    .border(
        width = 1.dp,
        color = if (selected) RexColor.primary else RexColor.border,
        shape = RoundedCornerShape(14.dp),
    )
    .clickable(enabled = enabled, onClick = onClick)

/**
 * The two states that are not the form. Written out rather than left as a
 * spinner or a blank: each says what is happening and what to do about it,
 * and both keep Cancel so nobody is stuck on a screen they cannot use.
 */
@Composable
private fun Notice(
    heading: String,
    body: String,
    onCancel: () -> Unit,
    busy: Boolean = false,
) {
    Box(Modifier.fillMaxSize(), Alignment.Center) {
        Column(
            Modifier.padding(32.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            if (busy) {
                CircularProgressIndicator(color = RexColor.primary, modifier = Modifier.size(24.dp))
                Spacer(Modifier.height(16.dp))
            }
            Text(
                heading,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                color = RexColor.foreground,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                body,
                color = RexColor.mutedForeground,
                fontSize = 13.sp,
                textAlign = TextAlign.Center,
            )
            Spacer(Modifier.height(16.dp))
            TextButton(onClick = onCancel) {
                Text("Back", color = RexColor.primary)
            }
        }
    }
}
