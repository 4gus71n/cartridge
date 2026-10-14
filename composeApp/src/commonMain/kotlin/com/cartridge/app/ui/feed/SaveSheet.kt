package com.cartridge.app.ui.feed

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cartridge.app.state.AppState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SaveSheet(state: AppState) {
    val cartridge = state.saveSheetFor ?: return
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val isSaved = state.savedIds.contains(cartridge.id)

    ModalBottomSheet(
        onDismissRequest = { state.closeSaveSheet() },
        sheetState = sheetState,
        containerColor = Color(0xFF141419),
        dragHandle = { BottomSheetDefaults.DragHandle() },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 20.dp)
                .padding(bottom = 36.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                text = "Save ${cartridge.title}",
                color = Color.White,
                fontWeight = FontWeight.Bold,
                fontSize = 18.sp,
                modifier = Modifier.padding(bottom = 10.dp),
            )

            if (!isSaved) {
                SaveRow(
                    icon = Icons.Filled.Bookmark,
                    title = "All saved",
                    subtitle = "Quick save",
                ) { state.saveToAll(cartridge) }
            } else {
                SaveRow(
                    icon = Icons.Filled.Bookmark,
                    title = "Saved",
                    subtitle = "Tap to remove",
                    tint = Color(0xFFFDE047),
                ) { state.unsave(cartridge) }
            }

            state.collections.forEach { collection ->
                val inCollection = collection.slugs.contains(cartridge.id)
                SaveRow(
                    icon = Icons.Filled.Folder,
                    title = collection.name,
                    subtitle = if (inCollection) "Already in this collection"
                    else "${collection.slugs.size} games",
                    tint = if (inCollection) Color(0xFF4ADE80) else Color.White,
                ) {
                    if (!inCollection) state.saveToCollection(cartridge, collection.id)
                }
            }

            SaveRow(
                icon = Icons.Filled.Add,
                title = "New collection",
                subtitle = "Group saves by vibe",
            ) { state.showCreateCollection() }
        }
    }
}

@Composable
private fun SaveRow(
    icon: ImageVector,
    title: String,
    subtitle: String,
    tint: Color = Color.White,
    onClick: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick)
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(24.dp))
        Column {
            Text(title, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 15.sp)
            Text(subtitle, color = Color.White.copy(alpha = 0.55f), fontSize = 12.sp)
        }
    }
}

@Composable
fun CreateCollectionDialog(state: AppState) {
    if (!state.createCollectionVisible) return
    var name by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = { state.dismissCreateCollection() },
        containerColor = Color(0xFF141419),
        title = { Text("New collection", color = Color.White, fontWeight = FontWeight.Bold) },
        text = {
            OutlinedTextField(
                value = name,
                onValueChange = { name = it },
                singleLine = true,
                placeholder = { Text("e.g. Arcade classics") },
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            TextButton(onClick = { state.createCollection(name) }) {
                Text("Create", color = Color(0xFF7CB8FF))
            }
        },
        dismissButton = {
            TextButton(onClick = { state.dismissCreateCollection() }) {
                Text("Cancel", color = Color.White.copy(alpha = 0.7f))
            }
        },
    )
}
