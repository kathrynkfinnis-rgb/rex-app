package com.kathrynfinnis.rex.ui

import io.github.jan.supabase.exceptions.HttpRequestException
import io.github.jan.supabase.exceptions.RestException
import java.io.IOException

/**
 * Nov 4 — what went wrong, as a sentence that is safe to put on a screen.
 *
 * Written after the Collections tab rendered this, in full, at 14:32 on the
 * emulator:
 *
 *     Could not find the table 'public.lists' ...
 *     URL: https://uhpzkbkwxcgqfxmlyktj.supabase.co/rest/v1/lists?...
 *     Headers: [Authorization=[Bearer eyJhbGciOiJIUzI1NiIs...
 *
 * That last line is a live access token, printed at 16sp, for as long as the
 * error state is on screen. Anyone photographing the screen, screen-sharing,
 * or sending us a bug report has handed over the session.
 *
 * The cause is not any one screen. supabase-kt builds RestException.message by
 * appending the request URL and the request headers to the PostgREST error —
 * so `e.message` is never safe to display, in any catch block, anywhere. Five
 * screens each decided independently to show it, and each had the same sound
 * instinct: "Unable to resolve host" really is more use on a train than
 * "something went wrong". The instinct was right and the field was wrong.
 *
 * So: the exception's *type* and *status* decide the sentence, and the raw
 * text is never read. RestException carries error/description/statusCode as
 * separate properties precisely so callers don't have to parse message — but
 * `description` is server-controlled and `error` leaks schema details, so
 * neither is shown either. Status is the only thing consulted.
 *
 * AuthScreen does not use this and should not: it maps AuthErrorCode to
 * sentences about passwords and confirmation emails, which is a different
 * vocabulary from "the feed didn't load".
 */
fun readableFailure(e: Throwable): String = when {
    // Ours, from RexApi — thrown by us, so the text is known and safe. Worth
    // its own sentence because the fix is to sign in, not to retry.
    e.message?.contains("Not signed in", ignoreCase = true) == true ->
        "Your session has run out. Sign in again."

    // No network, or it died mid-request. The one failure the person can
    // actually do something about.
    e is HttpRequestException || e is IOException ->
        "Couldn't reach Rex. Check your connection and try again."

    e is RestException -> when (e.statusCode) {
        401, 403 -> "Your session has run out. Sign in again."

        // 404 from PostgREST means the table or column Rex asked for isn't
        // there — a mistake in the app, not something the person can fix by
        // retrying. Saying so is more honest than "check your connection",
        // and it is what sent us looking for hitlist_lists.
        404 -> "Rex asked for something that isn't there. That's a bug at our " +
            "end — it won't help to try again."

        in 500..599 -> "Rex's database is having a moment. Try again shortly."

        else -> "Rex couldn't load that. Try again in a moment."
    }

    else -> "Something went wrong between here and Rex. " +
        "Check your connection and try again."
}
