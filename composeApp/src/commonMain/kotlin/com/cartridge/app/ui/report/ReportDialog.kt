package com.cartridge.app.ui.report

import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cartridge.app.state.AppState

private const val REASON_BROKEN = "broken"
private const val REASON_GRAPHICS = "graphics"
private const val REASON_QUALITY = "quality"
private const val REASON_DESKTOP = "desktop"
private const val REASON_KEYBOARD = "keyboard"
private const val REASON_UNPLAYABLE = "unplayable"
private const val REASON_ADULT = "adult"
private const val REASON_OTHER = "other"
private const val REASON_REMOVE = "remove"

@Composable
fun ReportDialog(state: AppState) {
    val cartridge = state.reportFor ?: return
    var selected by remember(cartridge.id) { mutableStateOf<String?>(null) }
    var details by remember(cartridge.id) { mutableStateOf("") }

    val canSubmit = selected != null &&
        !state.reportSubmitting &&
        (selected != REASON_OTHER || details.trim().length >= 3)

    AlertDialog(
        onDismissRequest = { state.closeReport() },
        containerColor = Color(0xFF141419),
        title = {
            Text(
                text = "Report a problem",
                color = Color.White,
                fontWeight = FontWeight.Bold,
            )
        },
        text = {
            Column(
                verticalArrangement = Arrangement.spacedBy(6.dp),
                modifier = Modifier.verticalScroll(rememberScrollState()),
            ) {
                Text(
                    text = "${cartridge.title} — what's going on?",
                    color = Color.White.copy(alpha = 0.6f),
                    fontSize = 13.sp,
                    modifier = Modifier.padding(bottom = 6.dp),
                )

                ReportOption("Game doesn't work at all", selected == REASON_BROKEN) {
                    selected = REASON_BROKEN
                }
                ReportOption("Game works but the graphics are broken", selected == REASON_GRAPHICS) {
                    selected = REASON_GRAPHICS
                }
                ReportOption("The game quality isn't good", selected == REASON_QUALITY) {
                    selected = REASON_QUALITY
                }
                ReportOption("This is a desktop game", selected == REASON_DESKTOP) {
                    selected = REASON_DESKTOP
                }
                ReportOption("Wrong keyboard bindings", selected == REASON_KEYBOARD) {
                    selected = REASON_KEYBOARD
                }
                ReportOption("Utterly broken", selected == REASON_UNPLAYABLE) {
                    selected = REASON_UNPLAYABLE
                }
                ReportOption("Improper or adult content", selected == REASON_ADULT) {
                    selected = REASON_ADULT
                }
                ReportOption("Other", selected == REASON_OTHER) {
                    selected = REASON_OTHER
                }
                ReportOption(
                    label = "Remove from catalog",
                    selected = selected == REASON_REMOVE,
                    danger = true,
                ) {
                    selected = REASON_REMOVE
                }

                if (selected == REASON_OTHER) {
                    OutlinedTextField(
                        value = details,
                        onValueChange = { details = it },
                        modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                        placeholder = { Text("Describe what's happening...") },
                        minLines = 3,
                        maxLines = 5,
                    )
                }

                state.reportError?.let { error ->
                    Text(
                        text = error,
                        color = Color(0xFFF87171),
                        fontSize = 12.sp,
                        modifier = Modifier.padding(top = 6.dp),
                    )
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { selected?.let { state.submitReport(cartridge, it, details) } },
                enabled = canSubmit,
            ) {
                if (state.reportSubmitting) {
                    CircularProgressIndicator(
                        color = Color.White,
                        strokeWidth = 2.dp,
                        modifier = Modifier.size(16.dp),
                    )
                } else {
                    Text("Submit", color = if (canSubmit) Color(0xFF7CB8FF) else Color.White.copy(alpha = 0.4f))
                }
            }
        },
        dismissButton = {
            TextButton(onClick = { state.closeReport() }) {
                Text("Cancel", color = Color.White.copy(alpha = 0.7f))
            }
        },
    )
}

@Composable
private fun ReportOption(
    label: String,
    selected: Boolean,
    danger: Boolean = false,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 2.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(4.dp),
    ) {
        RadioButton(
            selected = selected,
            onClick = null,
            colors = RadioButtonDefaults.colors(
                selectedColor = if (danger) Color(0xFFF87171) else Color(0xFF7C5CFF),
            ),
        )
        Text(
            text = label,
            color = if (danger) Color(0xFFF87171) else Color.White,
            fontSize = 14.sp,
        )
    }
}
