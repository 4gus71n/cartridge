package com.cartridge.app.ui.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Icon
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.cartridge.app.data.CollectionData
import com.cartridge.app.model.Cartridge
import com.cartridge.app.platform.PlatformBackHandler
import com.cartridge.app.platform.rememberUrlOpener
import com.cartridge.app.state.AppState

@Composable
fun ProfileOverlay(state: AppState) {
    if (!state.profileVisible) return
    val user = state.user ?: return
    val openUrl = rememberUrlOpener()

    PlatformBackHandler(enabled = true) { state.closeProfile() }

    var tab by remember { mutableStateOf(0) }
    var confirmDelete by remember { mutableStateOf(false) }
    if (confirmDelete) {
        DeleteAccountDialog(state = state, onDismiss = { confirmDelete = false; state.deleteError = null })
    }
    var openCollection by remember { mutableStateOf<CollectionData?>(null) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF0B0B0F))
            .statusBarsPadding(),
    ) {
        Column(modifier = Modifier.fillMaxSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                IconButton(
                    onClick = {
                        if (openCollection != null) openCollection = null else state.closeProfile()
                    },
                ) {
                    Icon(
                        Icons.AutoMirrored.Filled.ArrowBack,
                        contentDescription = "Back",
                        tint = Color.White,
                    )
                }
                Text(
                    text = if (openCollection != null) openCollection!!.name else "Profile",
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    fontSize = 18.sp,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = { state.logout() }) {
                    Icon(
                        Icons.AutoMirrored.Filled.Logout,
                        contentDescription = "Log out",
                        tint = Color.White.copy(alpha = 0.8f),
                    )
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(56.dp)
                        .clip(CircleShape)
                        .background(Brush.linearGradient(listOf(Color(0xFF7C5CFF), Color(0xFF22D3EE)))),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = user.email.take(1).uppercase(),
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                        fontSize = 22.sp,
                    )
                }
                Column {
                    Text(
                        text = user.email,
                        color = Color.White,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 15.sp,
                    )
                    Text(
                        text = "${state.likedCartridges().size} liked · " +
                            "${state.savedCartridges().size} saved · " +
                            "${state.collections.size} collections",
                        color = Color.White.copy(alpha = 0.55f),
                        fontSize = 12.sp,
                    )
                }
            }

            Row(modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp)) {
                ProfileTab("Liked", tab == 0, Modifier.weight(1f)) {
                    tab = 0; openCollection = null
                }
                ProfileTab("Saved", tab == 1, Modifier.weight(1f)) {
                    tab = 1; openCollection = null
                }
                ProfileTab("Collections", tab == 2, Modifier.weight(1f)) {
                    tab = 2; openCollection = null
                }
            }

            Box(modifier = Modifier.weight(1f)) {
                val collection = openCollection
                when {
                    collection != null -> GameList(
                        state = state,
                        games = state.collectionCartridges(collection),
                        emptyText = "Nothing in this collection yet.",
                        onPlay = { state.closeProfile(); state.play(it) },
                    )
                    tab == 0 -> GameList(
                        state = state,
                        games = state.likedCartridges(),
                        emptyText = "Games you like will show up here.",
                        onPlay = { state.closeProfile(); state.play(it) },
                    )
                    tab == 1 -> GameList(
                        state = state,
                        games = state.savedCartridges(),
                        emptyText = "Save games to play them offline.",
                        onPlay = { state.closeProfile(); state.play(it) },
                    )
                    else -> CollectionsList(
                        state = state,
                        onOpen = { openCollection = it },
                    )
                }
            }

            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .padding(horizontal = 20.dp, vertical = 6.dp),
            ) {
                TextButton(onClick = { openUrl(state.portalUrl) }) {
                    Text(
                        text = "Submit your game →",
                        color = Color(0xFF7CB8FF),
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                Row(verticalAlignment = Alignment.CenterVertically) {
                    listOf("Terms" to "terms", "Privacy" to "privacy", "Contact" to "takedown").forEach { (label, page) ->
                        Text(
                            text = label,
                            color = Color.White.copy(alpha = 0.55f),
                            fontSize = 13.sp,
                            modifier = Modifier
                                .clickable { openUrl(state.legalUrl(page)) }
                                .padding(horizontal = 12.dp, vertical = 8.dp),
                        )
                    }
                    Box(Modifier.weight(1f))
                    Text(
                        text = "Delete account",
                        color = Color(0xFFFF7A7A).copy(alpha = 0.8f),
                        fontSize = 13.sp,
                        modifier = Modifier
                            .clickable { confirmDelete = true }
                            .padding(horizontal = 12.dp, vertical = 8.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun ProfileTab(
    label: String,
    selected: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = modifier.clickable(onClick = onClick),
    ) {
        Text(
            text = label,
            color = if (selected) Color.White else Color.White.copy(alpha = 0.45f),
            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
            fontSize = 14.sp,
        )
        Box(
            modifier = Modifier
                .padding(top = 6.dp)
                .height(3.dp)
                .fillMaxWidth()
                .background(if (selected) Color(0xFF7C5CFF) else Color.Transparent),
        )
    }
}

@Composable
private fun GameList(
    state: AppState,
    games: List<Cartridge>,
    emptyText: String,
    onPlay: (Cartridge) -> Unit,
) {
    if (games.isEmpty()) {
        Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(emptyText, color = Color.White.copy(alpha = 0.45f), fontSize = 13.sp)
        }
        return
    }
    LazyColumn(modifier = Modifier.fillMaxSize()) {
        items(games, key = { it.id }) { cartridge ->
            val offlineReady = cartridge.bundled || state.gameStorage.isInstalled(cartridge.id)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { onPlay(cartridge) }
                    .padding(horizontal = 20.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                Box(
                    modifier = Modifier
                        .size(40.dp)
                        .clip(CircleShape)
                        .background(
                            Brush.linearGradient(listOf(cartridge.accentTop, cartridge.accentBottom)),
                        ),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        text = cartridge.title.take(1).uppercase(),
                        color = Color.White,
                        fontWeight = FontWeight.Bold,
                    )
                }
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = cartridge.title,
                        color = Color.White,
                        fontWeight = FontWeight.SemiBold,
                        fontSize = 15.sp,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    Text(
                        text = "by ${cartridge.author.name}",
                        color = Color.White.copy(alpha = 0.55f),
                        fontSize = 12.sp,
                    )
                }
                if (offlineReady) {
                    Icon(
                        Icons.Filled.CloudDone,
                        contentDescription = "Ready offline",
                        tint = Color(0xFF4ADE80),
                        modifier = Modifier.size(18.dp),
                    )
                }
                Icon(
                    Icons.Filled.PlayArrow,
                    contentDescription = "Play",
                    tint = Color.White.copy(alpha = 0.8f),
                )
            }
        }
    }
}

@Composable
private fun CollectionsList(
    state: AppState,
    onOpen: (CollectionData) -> Unit,
) {
    Column(modifier = Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .clickable { state.showCreateCollection() }
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Icon(Icons.Filled.Add, contentDescription = null, tint = Color(0xFF7CB8FF))
            Text("New collection", color = Color(0xFF7CB8FF), fontWeight = FontWeight.SemiBold)
        }
        if (state.collections.isEmpty()) {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text(
                    "Collections let you group saves — like playlists.",
                    color = Color.White.copy(alpha = 0.45f),
                    fontSize = 13.sp,
                )
            }
            return
        }
        LazyColumn(modifier = Modifier.fillMaxSize()) {
            items(state.collections, key = { it.id }) { collection ->
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onOpen(collection) }
                        .padding(horizontal = 20.dp, vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    Icon(Icons.Filled.Folder, contentDescription = null, tint = Color.White)
                    Column(modifier = Modifier.weight(1f)) {
                        Text(
                            collection.name,
                            color = Color.White,
                            fontWeight = FontWeight.SemiBold,
                            fontSize = 15.sp,
                        )
                        Text(
                            "${collection.slugs.size} games",
                            color = Color.White.copy(alpha = 0.55f),
                            fontSize = 12.sp,
                        )
                    }
                    IconButton(onClick = { state.deleteCollection(collection.id) }) {
                        Icon(
                            Icons.Filled.Delete,
                            contentDescription = "Delete collection",
                            tint = Color.White.copy(alpha = 0.4f),
                            modifier = Modifier.size(18.dp),
                        )
                    }
                }
            }
        }
    }
}


@Composable
private fun DeleteAccountDialog(state: AppState, onDismiss: () -> Unit) {
    var password by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = { if (!state.deleting) onDismiss() },
        title = { Text("Delete account?") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    "This permanently deletes your email, likes, saves, collections and comments. " +
                        "Games you published stay up under their license. This can't be undone.",
                    fontSize = 14.sp,
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("Password") },
                    singleLine = true,
                    visualTransformation = PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    isError = state.deleteError != null,
                    supportingText = state.deleteError?.let { { Text(it) } },
                )
            }
        },
        confirmButton = {
            TextButton(
                enabled = password.isNotBlank() && !state.deleting,
                onClick = { state.deleteAccount(password, onDone = onDismiss) },
            ) { Text(if (state.deleting) "Deleting…" else "Delete forever", color = Color(0xFFFF5A5A)) }
        },
        dismissButton = {
            TextButton(enabled = !state.deleting, onClick = onDismiss) { Text("Cancel") }
        },
    )
}
