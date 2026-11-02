package com.kathrynfinnis.rex.data

import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

/**
 * Signing in, and knowing whether you are.
 *
 * Nov 2 — the first thing the Android app needed and the one thing it had
 * none of. Every query below RexApi depends on a session: the row-level
 * security that decides what a person can see keys off auth.uid(), so an
 * unauthenticated client sees an empty database rather than an error. A feed
 * that renders nothing is what "no auth" looks like from the outside, which
 * is why this comes before any screen.
 *
 * Deliberately thin. supabase-kt already persists the session, refreshes the
 * token and exposes the status as a flow; wrapping that in a repository of
 * our own would be inventing a second source of truth for something the SDK
 * is already the truth about. What this adds is REX's vocabulary — signed in
 * or not, and who — so screens never import the Supabase types directly and
 * swapping the client later touches one file.
 *
 * What it does NOT do, on purpose:
 *
 *  - No Sign in with Apple. iOS has it (apple-account, the edge function) and
 *    Android does not need it: Apple only requires it where it is offered
 *    alongside other social sign-in, and this app offers none.
 *  - No password reset yet. It belongs in the sign-in screen's own work, and
 *    putting a half-wired button here would be worse than not having one.
 */
object RexAuth {

    /** Whether somebody is signed in right now, as a stream the UI can hold. */
    val isSignedIn: Flow<Boolean> =
        Rex.client.auth.sessionStatus.map { it is SessionStatus.Authenticated }

    /**
     * Still settling. The SDK reads a stored session from disk on launch, and
     * for that moment it is neither signed in nor signed out — showing the
     * sign-in screen during it would flash a login at somebody who is already
     * signed in, every single launch.
     */
    val isResolving: Flow<Boolean> =
        Rex.client.auth.sessionStatus.map { it is SessionStatus.Initializing }

    /** The signed-in person's id, or null. The same uuid as profiles.id. */
    val currentUserId: String?
        get() = Rex.client.auth.currentUserOrNull()?.id

    suspend fun signIn(email: String, password: String) {
        Rex.client.auth.signInWith(Email) {
            this.email = email.trim()
            this.password = password
        }
    }

    /**
     * Signing up does not sign you in if the project requires a confirmed
     * email — the caller has to look at what comes back rather than assume.
     * Returns true when there is a session afterwards.
     */
    suspend fun signUp(email: String, password: String): Boolean {
        Rex.client.auth.signUpWith(Email) {
            this.email = email.trim()
            this.password = password
        }
        return Rex.client.auth.currentSessionOrNull() != null
    }

    suspend fun signOut() {
        Rex.client.auth.signOut()
    }
}
