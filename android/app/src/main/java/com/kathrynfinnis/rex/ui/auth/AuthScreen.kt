package com.kathrynfinnis.rex.ui.auth

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.MailOutline
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import com.kathrynfinnis.rex.data.RexAuth
import com.kathrynfinnis.rex.ui.theme.RexColor
import io.github.jan.supabase.auth.exception.AuthErrorCode
import io.github.jan.supabase.auth.exception.AuthRestException
import io.github.jan.supabase.exceptions.HttpRequestException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.launch
import java.io.IOException

/**
 * Sign in and sign up, as one screen with a mode toggle.
 *
 * iOS splits this across three screens — a landing page, "Welcome back" and
 * "Get started" (LoginView.swift) — because it has a NavigationStack to push
 * them onto and an Apple button that needs room. Here it is one screen that
 * toggles, which is the one judgement call worth recording: navigation in this
 * build is wired up by hand afterwards, so a screen that needs two routes to
 * be usable is a screen that is not usable yet. The copy, the field order and
 * the 6-character minimum are lifted from those iOS screens so the two apps
 * ask for the same things in the same words.
 *
 * CONTRACT
 *
 *  - The caller owns RexAuth.isResolving. While it is true the SDK is still
 *    reading a stored session off disk, and this screen must not be on screen:
 *    showing it would flash a login at somebody who is already signed in, on
 *    every single launch. This composable deliberately does not read that flow
 *    itself — a screen that can decide not to be shown is a screen that fights
 *    whatever is routing it.
 *  - onSignedIn fires once there is a live session, from the main thread.
 *    RexAuth.isSignedIn flips at the same moment, so a caller observing that
 *    flow may find the callback redundant; it exists because iOS's LoginView
 *    has the same hook and because routing on an explicit event is easier to
 *    follow than routing on a flow that can also change for other reasons
 *    (a token refresh failing, a sign-out elsewhere).
 *  - It never signs anybody out and never reads any other table, so it is
 *    safe to show above the tab bar or in place of it.
 *
 * Not here, and not pretending to be: Sign in with Apple (RexAuth explains why
 * Android does not need it), password reset (RexAuth has no call for it yet —
 * a button that opened nothing would be worse than no button), and the
 * browse-without-an-account route iOS added for App Store 5.1.1(v), which
 * needs a second destination this build has no navigation for.
 */
@Composable
fun AuthScreen(onSignedIn: () -> Unit) {
    var mode by rememberSaveable { mutableStateOf(Mode.SignIn) }
    var email by rememberSaveable { mutableStateOf("") }
    // Password is remember, not rememberSaveable, on purpose: saved instance
    // state is written to disk by the system and survives process death, and a
    // password has no business being there. Losing it on rotation is the right
    // trade.
    var password by remember { mutableStateOf("") }
    var revealPassword by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var notice by remember { mutableStateOf<Notice?>(null) }
    // Sign-up succeeded but the project wants the email confirmed first, so
    // there is no session. A real state of its own rather than an error: the
    // account exists, and the only thing left to do is in their inbox.
    var awaitingConfirmation by rememberSaveable { mutableStateOf(false) }

    val scope = rememberCoroutineScope()
    val focus = LocalFocusManager.current

    val trimmedEmail = email.trim()
    // Only "has an @ in it". Anything cleverer rejects addresses that work —
    // single-label hosts on an office network, new top-level domains — and the
    // server is the authority on this anyway. iOS checks nothing but emptiness
    // and is no worse for it.
    val emailLooksLikeOne = trimmedEmail.contains('@') && !trimmedEmail.startsWith('@')
    val canSubmit = !busy && trimmedEmail.isNotEmpty() && password.isNotEmpty()

    fun submit() {
        focus.clearFocus()
        notice = when {
            !emailLooksLikeOne ->
                Notice("That email address doesn't look right. Check it and try again.", isProblem = true)
            // Only on the way in: an existing account may predate the rule, and
            // rejecting a password the server would accept locks somebody out
            // of their own account.
            mode == Mode.SignUp && password.length < MIN_PASSWORD_LENGTH ->
                Notice("Your password needs at least $MIN_PASSWORD_LENGTH characters.", isProblem = true)
            else -> null
        }
        if (notice != null) return

        busy = true
        scope.launch {
            try {
                when (mode) {
                    Mode.SignIn -> {
                        RexAuth.signIn(trimmedEmail, password)
                        onSignedIn()
                    }
                    Mode.SignUp -> {
                        if (RexAuth.signUp(trimmedEmail, password)) {
                            onSignedIn()
                        } else {
                            // No session means the project requires a confirmed
                            // email. Nothing failed; say so.
                            password = ""
                            awaitingConfirmation = true
                        }
                    }
                }
            } catch (cancelled: CancellationException) {
                // The screen went away mid-request. Not ours to report.
                throw cancelled
            } catch (e: Exception) {
                notice = Notice(readable(e, mode), isProblem = true)
            } finally {
                busy = false
            }
        }
    }

    Surface(color = RexColor.background, modifier = Modifier.fillMaxSize()) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .imePadding()
                .padding(horizontal = 24.dp, vertical = 32.dp),
        ) {
            Spacer(Modifier.height(24.dp))

            Text(
                text = if (awaitingConfirmation) "Check your inbox" else mode.title,
                style = MaterialTheme.typography.headlineMedium,
                color = RexColor.foreground,
            )
            Spacer(Modifier.height(8.dp))
            Text(
                // The exact sentence the brief asks for, because it is the one
                // thing somebody in this state needs to be told.
                text = if (awaitingConfirmation) {
                    "Check your email to confirm your account. Tap the link we've sent and you're in."
                } else {
                    mode.blurb
                },
                style = MaterialTheme.typography.bodyLarge,
                color = RexColor.mutedForeground,
            )

            Spacer(Modifier.height(32.dp))

            if (awaitingConfirmation) {
                ConfirmationState(
                    email = trimmedEmail,
                    onBackToSignIn = {
                        awaitingConfirmation = false
                        mode = Mode.SignIn
                        notice = null
                    },
                )
                return@Column
            }

            OutlinedTextField(
                value = email,
                onValueChange = { email = it; notice = null },
                label = { Text("Email") },
                singleLine = true,
                enabled = !busy,
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Email,
                    imeAction = ImeAction.Next,
                ),
                colors = rexFieldColours(),
                shape = FieldShape,
                modifier = Modifier.fillMaxWidth(),
            )

            Spacer(Modifier.height(12.dp))

            OutlinedTextField(
                value = password,
                onValueChange = { password = it; notice = null },
                // iOS labels this field "Password (6+ characters)" on sign-up
                // only, and so does this: on the way back in the rule is the
                // server's business, and quoting it there implies the password
                // you already have is wrong.
                label = {
                    Text(
                        if (mode == Mode.SignUp) "Password ($MIN_PASSWORD_LENGTH+ characters)"
                        else "Password"
                    )
                },
                singleLine = true,
                enabled = !busy,
                visualTransformation =
                    if (revealPassword) VisualTransformation.None else PasswordVisualTransformation(),
                keyboardOptions = KeyboardOptions(
                    keyboardType = KeyboardType.Password,
                    imeAction = ImeAction.Done,
                ),
                keyboardActions = KeyboardActions(onDone = { if (canSubmit) submit() }),
                trailingIcon = {
                    // Android convention, and absent from iOS deliberately
                    // rather than by oversight: SecureField has no reveal, and
                    // a typo in a password you cannot see is the commonest
                    // reason a correct password "fails".
                    IconButton(onClick = { revealPassword = !revealPassword }) {
                        Icon(
                            imageVector =
                                if (revealPassword) Icons.Outlined.VisibilityOff
                                else Icons.Outlined.Visibility,
                            contentDescription =
                                if (revealPassword) "Hide password" else "Show password",
                            tint = RexColor.mutedForeground,
                        )
                    }
                },
                colors = rexFieldColours(),
                shape = FieldShape,
                modifier = Modifier.fillMaxWidth(),
            )

            notice?.let {
                Spacer(Modifier.height(12.dp))
                Text(
                    text = it.text,
                    style = MaterialTheme.typography.bodyMedium,
                    color = if (it.isProblem) RexColor.destructive else RexColor.moss,
                )
            }

            Spacer(Modifier.height(24.dp))

            Button(
                onClick = { submit() },
                enabled = canSubmit,
                shape = FieldShape,
                colors = ButtonDefaults.buttonColors(
                    containerColor = RexColor.primary,
                    contentColor = RexColor.primaryForeground,
                    disabledContainerColor = RexColor.disabled,
                    disabledContentColor = RexColor.primaryForeground,
                ),
                modifier = Modifier
                    .fillMaxWidth()
                    .height(52.dp),
            ) {
                if (busy) {
                    // Inside the button rather than over the screen: the rest of
                    // the form stays readable, and it is obvious which action is
                    // in flight.
                    CircularProgressIndicator(
                        color = RexColor.primaryForeground,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(20.dp),
                    )
                } else {
                    Text(mode.action, fontWeight = FontWeight.SemiBold)
                }
            }

            Spacer(Modifier.height(8.dp))

            TextButton(
                onClick = {
                    mode = mode.other
                    // Keep the email — it is almost always the same address, and
                    // somebody switching mode has usually just been told to.
                    // Clear the password: carrying it across means a typo made
                    // while signing in silently becomes the password on a new
                    // account.
                    password = ""
                    notice = null
                },
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(mode.other.switchInvite, color = RexColor.primary)
            }

            Spacer(Modifier.height(24.dp))

            if (mode == Mode.SignUp) {
                // Word for word the line on iOS's landing screen. iOS also has
                // an explicit tick box before sign-up (#182) backed by
                // recordConsent; see the notes returned with this file — it is
                // a real gap here, not a decision.
                Text(
                    text = "You must be 16 or over. By continuing you agree to the " +
                        "Terms of Service and Privacy Policy.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = RexColor.mutedForeground,
                )
            }
        }
    }
}

/**
 * After a sign-up that needs the email confirming. There is a way out of it —
 * the account exists, so the next thing they do here is sign in — and no
 * "resend" button, because RexAuth has no call for one.
 */
@Composable
private fun ConfirmationState(email: String, onBackToSignIn: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Icon(
            imageVector = Icons.Outlined.MailOutline,
            contentDescription = null,
            tint = RexColor.primary,
            modifier = Modifier.size(44.dp),
        )
        if (email.isNotEmpty()) {
            Text(
                text = "We've sent it to $email.",
                style = MaterialTheme.typography.bodyLarge,
                color = RexColor.foreground,
            )
        }
        Text(
            text = "Once you've confirmed, come back and sign in.",
            style = MaterialTheme.typography.bodyMedium,
            color = RexColor.mutedForeground,
        )
        TextButton(onClick = onBackToSignIn) {
            Text("Back to sign in", color = RexColor.primary)
        }
    }
}

private enum class Mode {
    SignIn, SignUp;

    /** Copy carried over from iOS's SignInScreen and SignUpScreen. */
    val title: String
        get() = if (this == SignIn) "Welcome back" else "Get started"

    val blurb: String
        get() = if (this == SignIn) {
            "Pick up where your friends left off."
        } else {
            "Books, films, places and trips — kept by your friends, not an algorithm."
        }

    val action: String
        get() = if (this == SignIn) "Sign in" else "Create account"

    /**
     * How this mode invites you into it, so the toggle under the button reads
     * `mode.other.switchInvite` — the offer, not the state you are in.
     */
    val switchInvite: String
        get() = if (this == SignIn) "I already have an account" else "New to Rex? Create an account"

    val other: Mode
        get() = if (this == SignIn) SignUp else SignIn
}

private data class Notice(val text: String, val isProblem: Boolean)

/** Supabase's own default, and the number iOS puts on the field. */
private const val MIN_PASSWORD_LENGTH = 6

private val FieldShape = RoundedCornerShape(12.dp)

@Composable
private fun rexFieldColours() = OutlinedTextFieldDefaults.colors(
    focusedBorderColor = RexColor.primary,
    unfocusedBorderColor = RexColor.border,
    disabledBorderColor = RexColor.border,
    focusedContainerColor = RexColor.card,
    unfocusedContainerColor = RexColor.card,
    disabledContainerColor = RexColor.card,
    focusedTextColor = RexColor.foreground,
    unfocusedTextColor = RexColor.foreground,
    disabledTextColor = RexColor.mutedForeground,
    focusedLabelColor = RexColor.primary,
    unfocusedLabelColor = RexColor.placeholder,
    disabledLabelColor = RexColor.placeholder,
    cursorColor = RexColor.primary,
)

/**
 * What went wrong, as a sentence rather than an exception.
 *
 * iOS shows error.localizedDescription here, which is how "Invalid login
 * credentials" and "AuthApiError: email rate limit exceeded" end up in front of
 * people. Deliberately different: supabase-kt gives a machine-readable
 * AuthErrorCode on the exception, and every code worth distinguishing gets its
 * own sentence saying what happened and what to do about it.
 *
 * The message fallback underneath is not belt-and-braces for its own sake —
 * older GoTrue responses carry no error code at all, so errorCode is null and
 * the string is all there is. Matching on it is fragile, which is exactly why
 * it sits second and why anything unrecognised gets a plain sentence instead of
 * the raw text.
 */
private fun readable(e: Throwable, mode: Mode): String {
    val fallback = if (mode == Mode.SignIn) {
        "Something went wrong signing you in. Try again in a moment."
    } else {
        "Something went wrong creating your account. Try again in a moment."
    }

    // No network, or it died mid-request. Worth its own sentence because the
    // fix is entirely in the person's hands.
    if (e is HttpRequestException || e is IOException) {
        return "Couldn't reach Rex. Check your connection and try again."
    }

    if (e is AuthRestException) {
        when (e.errorCode) {
            AuthErrorCode.InvalidCredentials, AuthErrorCode.UserNotFound ->
                return "That email and password don't match an account. Check both, " +
                    "or create an account if you're new to Rex."

            AuthErrorCode.EmailNotConfirmed ->
                return "Check your email to confirm your account, then sign in."

            AuthErrorCode.UserAlreadyExists, AuthErrorCode.EmailExists ->
                return "There's already an account with that email. Sign in instead."

            AuthErrorCode.WeakPassword ->
                return "That password is too easy to guess. Try a longer one."

            AuthErrorCode.ValidationFailed ->
                return "That email address doesn't look right. Check it and try again."

            AuthErrorCode.OverRequestRateLimit, AuthErrorCode.OverEmailSendRateLimit ->
                return "Too many attempts just now. Wait a minute and try again."

            AuthErrorCode.SignupDisabled, AuthErrorCode.EmailProviderDisabled ->
                return "New accounts aren't open at the moment."

            AuthErrorCode.EmailAddressNotAuthorized ->
                return "Rex can't send email to that address. Try another one."

            AuthErrorCode.UserBanned ->
                return "That account has been suspended."

            else -> Unit // Fall through to the message, then to the fallback.
        }
    }

    val raw = e.message?.lowercase().orEmpty()
    return when {
        raw.contains("invalid login credentials") ->
            "That email and password don't match an account. Check both, " +
                "or create an account if you're new to Rex."
        raw.contains("email not confirmed") ->
            "Check your email to confirm your account, then sign in."
        raw.contains("already registered") || raw.contains("already been registered") ->
            "There's already an account with that email. Sign in instead."
        raw.contains("password should be at least") ->
            "Your password needs at least $MIN_PASSWORD_LENGTH characters."
        raw.contains("rate limit") ->
            "Too many attempts just now. Wait a minute and try again."
        raw.contains("unable to validate email") || raw.contains("invalid email") ->
            "That email address doesn't look right. Check it and try again."
        else -> fallback
    }
}
