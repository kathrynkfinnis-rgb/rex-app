package com.kathrynfinnis.rex.ui.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kathrynfinnis.rex.data.FeedRecommendation
import com.kathrynfinnis.rex.data.Rex
import com.kathrynfinnis.rex.ui.add.Tier
import com.kathrynfinnis.rex.ui.add.TierChip
import com.kathrynfinnis.rex.ui.readableFailure
import com.kathrynfinnis.rex.ui.theme.RexColor
import kotlinx.coroutines.launch

/**
 * Nov 17 — changing or removing a Rex you have already posted. Until today
 * Android could create and never revise: you could post a Rex with a typo in
 * it and the only way to fix it was to pick up an iPhone.
 *
 * Narrower than EditRexView.swift on purpose, and the narrowness is the point.
 * iOS edits the rating, the note, the photos, the tagged friends and the
 * item's own title; this edits the rating and the note, because those are the
 * two things this platform has UI for. Rex.updateRecommendation patches only
 * those two columns for the same reason — anything wider would send empty
 * values for fields Android cannot show and wipe them.
 *
 * The rating control is the one from AddRexScreen rather than a second copy.
 * Its own comment explains why that matters more than it looks: the five
 * values are copied from RexRatingTier.representativeRawValue, and two
 * versions of them is how one tier becomes two numbers in the column.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun EditRexSheet(
    rec: FeedRecommendation,
    onDismiss: () -> Unit,
    onSaved: () -> Unit,
) {
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState()

    var tier by remember {
        // Back from the stored number to the tier that wrote it, so the sheet
        // opens on what the Rex actually says rather than a default.
        mutableStateOf(
            Tier.entries.minByOrNull { kotlin.math.abs(it.rating - rec.rating) } ?: Tier.Rex
        )
    }
    var note by remember { mutableStateOf(rec.note.orEmpty()) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var confirmingDelete by remember { mutableStateOf(false) }

    ModalBottomSheet(
        onDismissRequest = { if (!busy) onDismiss() },
        sheetState = sheetState,
        containerColor = RexColor.background,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .navigationBarsPadding()
                .padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
        ) {
            Text(
                rec.items?.title ?: "Your Rex",
                fontSize = 18.sp,
                fontWeight = FontWeight.SemiBold,
                color = RexColor.foreground,
            )
            Spacer(Modifier.height(16.dp))

            Text(
                "Your rating",
                fontSize = 12.sp,
                fontWeight = FontWeight.SemiBold,
                color = RexColor.mutedForeground,
            )
            Spacer(Modifier.height(8.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                Tier.entries.forEach { option ->
                    TierChip(
                        tier = option,
                        selected = option == tier,
                        enabled = !busy,
                        onClick = { tier = option },
                        modifier = Modifier.weight(1f),
                    )
                }
            }

            Spacer(Modifier.height(16.dp))
            OutlinedTextField(
                value = note,
                onValueChange = { note = it },
                enabled = !busy,
                label = { Text("Your note") },
                minLines = 3,
                shape = RoundedCornerShape(14.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedContainerColor = RexColor.card,
                    unfocusedContainerColor = RexColor.card,
                    focusedBorderColor = RexColor.primary,
                    unfocusedBorderColor = RexColor.border,
                    focusedTextColor = RexColor.foreground,
                    unfocusedTextColor = RexColor.foreground,
                    cursorColor = RexColor.primary,
                ),
                modifier = Modifier.fillMaxWidth(),
            )

            error?.let {
                Spacer(Modifier.height(8.dp))
                Text(it, fontSize = 13.sp, color = RexColor.destructive)
            }

            Spacer(Modifier.height(16.dp))
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
            ) {
                TextButton(
                    onClick = { confirmingDelete = true },
                    enabled = !busy,
                ) {
                    Text("Delete", color = RexColor.destructive, fontWeight = FontWeight.SemiBold)
                }
                Row {
                    TextButton(onClick = onDismiss, enabled = !busy) {
                        Text("Cancel", color = RexColor.mutedForeground)
                    }
                    TextButton(
                        enabled = !busy,
                        onClick = {
                            busy = true
                            error = null
                            scope.launch {
                                runCatching {
                                    Rex.updateRecommendation(rec.id, tier.rating, note)
                                }
                                    .onSuccess { onSaved() }
                                    .onFailure { error = readableFailure(it) }
                                busy = false
                            }
                        },
                    ) {
                        if (busy) {
                            CircularProgressIndicator(
                                color = RexColor.primary,
                                modifier = Modifier.size(18.dp),
                            )
                        } else {
                            Text("Save", color = RexColor.primary, fontWeight = FontWeight.SemiBold)
                        }
                    }
                }
            }
        }
    }

    if (confirmingDelete) {
        AlertDialog(
            onDismissRequest = { confirmingDelete = false },
            containerColor = RexColor.card,
            title = { Text("Delete this Rex?", color = RexColor.foreground) },
            // Said plainly, because it is true and it cannot be undone from
            // here or anywhere else in the app.
            text = {
                Text(
                    "“${rec.items?.title ?: "This"}” will be removed for good. " +
                        "This can't be undone.",
                    color = RexColor.mutedForeground,
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    confirmingDelete = false
                    busy = true
                    error = null
                    scope.launch {
                        runCatching { Rex.deleteRecommendation(rec.id) }
                            .onSuccess { onSaved() }
                            .onFailure { error = readableFailure(it) }
                        busy = false
                    }
                }) {
                    Text("Delete", color = RexColor.destructive, fontWeight = FontWeight.SemiBold)
                }
            },
            dismissButton = {
                TextButton(onClick = { confirmingDelete = false }) {
                    Text("Keep it", color = RexColor.primary)
                }
            },
        )
    }
}
