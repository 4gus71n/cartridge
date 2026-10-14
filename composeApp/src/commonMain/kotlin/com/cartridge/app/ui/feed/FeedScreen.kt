package com.cartridge.app.ui.feed

import androidx.compose.foundation.pager.VerticalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.Modifier
import com.cartridge.app.model.Cartridge
import com.cartridge.app.state.AppState

@Composable
fun FeedScreen(
    catalog: List<Cartridge>,
    state: AppState,
    modifier: Modifier = Modifier,
) {
    val pagerState = rememberPagerState(pageCount = { catalog.size })

    LaunchedEffect(pagerState.settledPage, catalog) {
        catalog.getOrNull(pagerState.settledPage)?.let(state::markSeen)
    }

    VerticalPager(
        state = pagerState,
        modifier = modifier,
        userScrollEnabled = state.playing == null,
    ) { page ->
        ReelCard(
            cartridge = catalog[page],
            state = state,
        )
    }
}
