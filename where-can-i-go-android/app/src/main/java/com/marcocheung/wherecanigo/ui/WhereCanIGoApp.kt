package com.marcocheung.wherecanigo.ui

import android.app.Activity
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutLinearInEasing
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.LinearOutSlowInEasing
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.slideOutHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.ui.graphics.graphicsLayer
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.activity.compose.BackHandler
import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.rememberDraggableState
import androidx.compose.foundation.gestures.draggable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.key
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.AlertDialog
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.saveable.SaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.layout.onSizeChanged
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.collapse
import androidx.compose.ui.semantics.expand
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import com.marcocheung.wherecanigo.R
import kotlin.math.abs
import kotlin.math.roundToInt

private enum class Destination(@param:StringRes val title: Int, @param:DrawableRes val icon: Int) {
    Overview(R.string.overview, R.drawable.ic_globe),
    Visas(R.string.my_visas, R.drawable.ic_visa),
    Travels(R.string.travels, R.drawable.ic_travel),
}

private enum class Page { Main, Profile, Settings }

@Composable
fun WhereCanIGoApp() {
    val darkTheme = isSystemInDarkTheme()
    val view = LocalView.current
    if (!view.isInEditMode) {
        SideEffect {
            val window = (view.context as Activity).window
            window.isNavigationBarContrastEnforced = false
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !darkTheme
                isAppearanceLightNavigationBars = !darkTheme
            }
        }
    }
    WhereCanIGoTheme(darkTheme) {
        val context = LocalContext.current
        val state = remember { AppState.get(context) }
        val locale = LocalConfiguration.current.locales[0]
        LaunchedEffect(locale) { state.ensureCountries(locale) }
        val lifecycle = LocalLifecycleOwner.current.lifecycle
        DisposableEffect(lifecycle) {
            val observer = LifecycleEventObserver { _, event ->
                if (event == Lifecycle.Event.ON_RESUME) state.refreshReferenceDate()
            }
            lifecycle.addObserver(observer)
            onDispose { lifecycle.removeObserver(observer) }
        }
        var page by rememberSaveable { mutableStateOf(Page.Main) }
        when {
            state.dataLoadFailed -> Column(
                Modifier.fillMaxSize().windowInsetsPadding(WindowInsets.safeDrawing).padding(24.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                ErrorText(stringResource(R.string.saved_data_error))
                TextButton(onClick = state::loadSavedData) { Text(stringResource(R.string.retry)) }
            }
            state.needsPassportSelection -> PassportGate(state)
            else -> {
                MainScreen(state, onOpenProfile = { page = Page.Profile }, onOpenSettings = { page = Page.Settings })
                if (page != Page.Main) {
                    androidx.compose.ui.window.Dialog(
                        onDismissRequest = { page = Page.Main },
                        properties = androidx.compose.ui.window.DialogProperties(
                            usePlatformDefaultWidth = false, decorFitsSystemWindows = false,
                        ),
                    ) {
                        when (page) {
                            Page.Profile -> ProfilePage(state) { page = Page.Main }
                            Page.Settings -> SettingsPage(state) { page = Page.Main }
                            Page.Main -> Unit
                        }
                    }
                }
            }
        }
        state.operationError?.let { message ->
            AlertDialog(
                onDismissRequest = state::clearError,
                text = { Text(stringResource(message)) },
                confirmButton = { TextButton(onClick = state::clearError) { Text(stringResource(R.string.ok)) } },
            )
        }
    }
}

/** Callbacks and state shared by the phone and wide layouts. */
private class MainActions(
    val state: AppState,
    val dice: DiceOptions,
    val destination: Destination,
    val selectedCode: String?,
    val select: (String?) -> Unit,
    val locate: (String) -> Unit,
    val openPolicy: (String) -> Unit,
    val addVisa: (String) -> Unit,
    val addVisit: (String) -> Unit,
    val addWishlist: (String) -> Unit,
    val reviewWishlist: (String) -> Unit,
    val openProfile: () -> Unit,
    val openSettings: () -> Unit,
    val panelState: SaveableStateHolder,
    val retainVisaDraft: () -> Boolean,
)

@Composable
private fun MainScreen(state: AppState, onOpenProfile: () -> Unit, onOpenSettings: () -> Unit) {
    val dice = rememberSaveable(saver = DiceOptions.Saver) { DiceOptions() }
    val panelState = rememberSaveableStateHolder()
    var destination by rememberSaveable { mutableStateOf(Destination.Overview) }
    var selectedCode by rememberSaveable { mutableStateOf<String?>(null) }
    var policyCode by rememberSaveable { mutableStateOf<String?>(null) }
    var flyRequest by remember { mutableStateOf<FlyRequest?>(null) }
    val camera = rememberSaveable(saver = MapCamera.Saver) { MapCamera() }
    val categoryByCode by remember(state) {
        derivedStateOf { state.countries.associate { it.code to state.eligibility(it.code).category } }
    }
    val actions = MainActions(
        state = state,
        dice = dice,
        destination = destination,
        selectedCode = selectedCode,
        select = { selectedCode = it },
        locate = {
            selectedCode = it
            flyRequest = FlyRequest(it)
        },
        openPolicy = { policyCode = it },
        addVisa = {
            state.pendingAddVisaCountryCode = it
            selectedCode = null
            destination = Destination.Visas
        },
        addVisit = {
            state.pendingAddVisitCountryCode = it; selectedCode = null; destination = Destination.Travels
        },
        addWishlist = {
            state.pendingAddWishlistCountryCode = it; selectedCode = null; destination = Destination.Travels
        },
        reviewWishlist = {
            state.pendingReviewWishlistCountryCode = it; selectedCode = null; destination = Destination.Travels
        },
        openProfile = onOpenProfile,
        openSettings = onOpenSettings,
        panelState = panelState,
        retainVisaDraft = { destination == Destination.Visas },
    )
    val onTab: (Destination) -> Unit = {
        destination = it
        selectedCode = null
    }
    val onCountrySelected: (MapCountry) -> Unit = { selectedCode = it.code }
    BackHandler(enabled = selectedCode != null) { selectedCode = null }
    Scaffold(
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        contentWindowInsets = WindowInsets.safeDrawing.only(WindowInsetsSides.Top + WindowInsetsSides.Horizontal),
    ) { insets ->
        BoxWithConstraints(Modifier.fillMaxSize().padding(insets)) {
            if (maxWidth >= 600.dp) {
                Row(
                    Modifier.fillMaxSize()
                        .windowInsetsPadding(WindowInsets.navigationBars)
                        .testTag("wide-layout"),
                ) {
                    NavigationRail(containerColor = MaterialTheme.colorScheme.surfaceContainer) {
                        Spacer(Modifier.height(24.dp))
                        Destination.entries.forEach { item ->
                            NavigationRailItem(
                                modifier = Modifier.testTag("tab-${item.name}"),
                                selected = destination == item,
                                onClick = { onTab(item) },
                                icon = { AnimatedNavIcon(item, destination == item, androidx.compose.material3.LocalContentColor.current) },
                                label = { Text(stringResource(item.title)) },
                            )
                        }
                    }
                    Column(Modifier.width(360.dp).padding(12.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        selectedCode?.let { code -> SelectedCountryCard(actions, code) }
                        Surface(
                            modifier = Modifier.weight(1f),
                            shape = RoundedCornerShape(24.dp),
                            color = MaterialTheme.colorScheme.surfaceContainer,
                        ) {
                            Column {
                                SheetHeader(
                                    state, dice,
                                    onDicePicked = actions.locate,
                                    onOpenProfile = onOpenProfile,
                                    onOpenSettings = onOpenSettings,
                                    modifier = Modifier.padding(top = 12.dp),
                                )
                                PanelContent(actions)
                            }
                        }
                    }
                    WorldMap(
                        camera,
                        selectedCode,
                        categoryByCode,
                        onCountrySelected,
                        Modifier.weight(1f).fillMaxSize(),
                        flyRequest = flyRequest,
                        visitedCodes = state.data.visitedCountryCodes,
                    )
                }
            } else {
                PhoneContent(
                    actions, camera, categoryByCode, flyRequest, onCountrySelected, onTab,
                    Modifier.fillMaxSize().testTag("compact-layout"),
                )
            }
        }
    }
    policyCode?.let { code ->
        key(code) { EntryPolicySheet(state, code) { policyCode = null } }
    }
}

@Composable
private fun SelectedCountryCard(actions: MainActions, code: String, modifier: Modifier = Modifier) {
    CountryCard(
        actions.state,
        code,
        onOpen = { actions.openPolicy(code) },
        onAddVisa = { actions.addVisa(code) },
        onAddVisit = { actions.addVisit(code) },
        onAddWishlist = { actions.addWishlist(code) },
        onReviewWishlist = { actions.reviewWishlist(code) },
        onClose = { actions.select(null) },
        modifier = modifier,
    )
}

private enum class PanelDetent { Peek, Half, Expanded }

private val FloatingBarHeight = 64.dp
private val FloatingBarMargin = 12.dp
private val DefaultHeaderHeight = 104.dp
private val DefaultPeekContent = 120.dp

@Composable
@OptIn(ExperimentalMaterial3Api::class)
private fun PhoneContent(
    actions: MainActions,
    camera: MapCamera,
    categoryByCode: Map<String, VisaCategory>,
    flyRequest: FlyRequest?,
    onCountrySelected: (MapCountry) -> Unit,
    onTab: (Destination) -> Unit,
    modifier: Modifier = Modifier,
) {
    val density = LocalDensity.current
    val navInset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    // Area at the bottom of the panel covered by the floating navigation bar.
    val barZone = navInset + FloatingBarMargin + FloatingBarHeight + FloatingBarMargin
    var cardHeight by remember { mutableStateOf(140.dp) }
    var headerHeight by remember { mutableStateOf(DefaultHeaderHeight) }
    var peekContent by rememberSaveable(stateSaver = DpSaver) { mutableStateOf(DefaultPeekContent) }
    var containerHeightPx by remember { mutableFloatStateOf(0f) }
    var detent by rememberSaveable { mutableStateOf(PanelDetent.Peek) }
    var dragging by remember { mutableStateOf(false) }
    var dragOffsetPx by remember { mutableFloatStateOf(Float.NaN) }
    val peekHeightPx = with(density) { (headerHeight + peekContent + barZone).toPx() }
    val peekOffset = (containerHeightPx - peekHeightPx).coerceAtLeast(0f)
    val halfOffset = minOf(containerHeightPx * 0.42f, peekOffset)
    val targetOffset = when (detent) {
        PanelDetent.Peek -> peekOffset
        PanelDetent.Half -> halfOffset
        PanelDetent.Expanded -> 0f
    }
    val animatedOffset by androidx.compose.animation.core.animateFloatAsState(targetOffset, label = "panel-offset")
    val panelOffset = if (dragging && dragOffsetPx.isFinite()) dragOffsetPx else animatedOffset
    val visibleHeight = with(density) { (containerHeightPx - panelOffset).coerceAtLeast(0f).toDp() }
    fun nearestDetent(offset: Float): PanelDetent = listOf(
        PanelDetent.Peek to peekOffset,
        PanelDetent.Half to halfOffset,
        PanelDetent.Expanded to 0f,
    ).minBy { abs(it.second - offset) }.first
    fun beginDrag() {
        if (!dragging) {
            dragOffsetPx = animatedOffset
            dragging = true
        }
    }
    fun settleDrag() {
        if (dragging) {
            detent = nearestDetent(dragOffsetPx)
            dragging = false
        }
    }
    val nestedScrollConnection = remember(peekOffset, halfOffset, animatedOffset) {
        object : NestedScrollConnection {
            override fun onPostScroll(consumed: Offset, available: Offset, source: NestedScrollSource): Offset {
                if (available.y == 0f || containerHeightPx == 0f) return Offset.Zero
                beginDrag()
                val old = dragOffsetPx
                dragOffsetPx = (old + available.y).coerceIn(0f, peekOffset)
                return Offset(0f, dragOffsetPx - old)
            }

            override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity {
                settleDrag()
                return Velocity.Zero
            }
        }
    }
    val dragState = rememberDraggableState { delta ->
        beginDrag()
        dragOffsetPx = (dragOffsetPx + delta).coerceIn(0f, peekOffset)
    }
    val collapse: () -> Unit = {
        detent = when (detent) {
            PanelDetent.Expanded -> PanelDetent.Half
            PanelDetent.Half -> PanelDetent.Peek
            PanelDetent.Peek -> PanelDetent.Peek
        }
    }
    LaunchedEffect(actions.destination) {
        if (actions.destination == Destination.Travels) detent = PanelDetent.Expanded
    }
    BackHandler(enabled = detent != PanelDetent.Peek && actions.selectedCode == null) { collapse() }
    Box(
        modifier.fillMaxSize().clipToBounds().testTag("bottom-sheet")
            .onSizeChanged { containerHeightPx = it.height.toFloat() },
    ) {
        WorldMap(
            camera,
            actions.selectedCode,
            categoryByCode,
            onCountrySelected,
            Modifier.fillMaxSize(),
            flyRequest = flyRequest,
            cameraBottomPadding = visibleHeight + cardHeight + 24.dp,
            visitedCodes = actions.state.data.visitedCountryCodes,
        ) {
            actions.selectedCode?.takeIf { detent != PanelDetent.Expanded }?.let { code ->
                SelectedCountryCard(
                    actions,
                    code,
                    Modifier.align(Alignment.BottomCenter).padding(start = 12.dp, end = 12.dp, bottom = visibleHeight + 12.dp)
                        .onSizeChanged { cardHeight = with(density) { it.height.toDp() } },
                )
            }
        }
        val sheetShape = RoundedCornerShape(topStart = 28.dp, topEnd = 28.dp)
        if (containerHeightPx > 0f) Column(
            Modifier.align(Alignment.BottomCenter).fillMaxWidth().height(visibleHeight)
                .shadow(8.dp, sheetShape, clip = false)
                .clip(sheetShape)
                .background(MaterialTheme.colorScheme.surfaceContainer)
                .nestedScroll(nestedScrollConnection),
        ) {
            val handleLabel = stringResource(R.string.sheet_drag_handle)
            val detentLabel = stringResource(when (detent) {
                PanelDetent.Peek -> R.string.sheet_peek
                PanelDetent.Half -> R.string.sheet_half
                PanelDetent.Expanded -> R.string.sheet_expanded
            })
            Column(
                Modifier.fillMaxWidth()
                    .draggable(state = dragState, orientation = Orientation.Vertical, onDragStopped = { settleDrag() })
                    .onSizeChanged { headerHeight = with(density) { it.height.toDp() } },
            ) {
                Box(
                    Modifier.fillMaxWidth().height(24.dp).clickable {
                        detent = when (detent) {
                            PanelDetent.Peek -> PanelDetent.Half
                            PanelDetent.Half -> PanelDetent.Expanded
                            PanelDetent.Expanded -> PanelDetent.Peek
                        }
                    }.semantics {
                        contentDescription = handleLabel
                        stateDescription = detentLabel
                        collapse { detent = PanelDetent.Peek; true }
                        expand { detent = PanelDetent.Expanded; true }
                    }.testTag("sheet-handle"),
                    contentAlignment = Alignment.Center,
                ) {
                    Box(
                        Modifier.size(width = 32.dp, height = 4.dp).clip(CircleShape)
                            .background(MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f)),
                    )
                }
                SheetHeader(
                    actions.state, actions.dice,
                    onDicePicked = { actions.locate(it); detent = PanelDetent.Peek },
                    onOpenProfile = actions.openProfile,
                    onOpenSettings = actions.openSettings,
                )
            }
            CompositionLocalProvider(
                LocalSheetBottomPadding provides barZone,
                LocalPeekContentReporter provides { if (it > 0.dp) peekContent = it },
            ) {
                PanelContent(actions, onLocate = { actions.locate(it); detent = PanelDetent.Peek }, modifier = Modifier.weight(1f))
            }
        }
        FloatingNavBar(
            selected = actions.destination,
            onSelect = onTab,
            modifier = Modifier.align(Alignment.BottomCenter)
                .padding(bottom = navInset + FloatingBarMargin, start = 16.dp, end = 16.dp),
        )
    }
}

private val DpSaver = androidx.compose.runtime.saveable.Saver<androidx.compose.ui.unit.Dp, Float>(
    save = { it.value },
    restore = { it.dp },
)

/**
 * Material 3 Expressive style floating navigation bar: a pill that floats over the
 * panel; the selected destination expands into a tonal pill showing icon and label.
 */
@Composable
private fun FloatingNavBar(selected: Destination, onSelect: (Destination) -> Unit, modifier: Modifier = Modifier) {
    Surface(
        modifier = modifier.height(FloatingBarHeight),
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceContainerLowest,
        shadowElevation = 6.dp,
        tonalElevation = 2.dp,
    ) {
        Row(
            Modifier.fillMaxHeight().selectableGroup().padding(6.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Destination.entries.forEach { item ->
                val isSelected = item == selected
                val container by animateColorAsState(
                    if (isSelected) MaterialTheme.colorScheme.primaryContainer else Color.Transparent, label = "nav-container",
                )
                val content by animateColorAsState(
                    if (isSelected) MaterialTheme.colorScheme.onPrimaryContainer else MaterialTheme.colorScheme.onSurfaceVariant,
                    label = "nav-content",
                )
                Row(
                    Modifier.weight(1f, fill = false).fillMaxHeight().clip(CircleShape).background(container)
                        .selectable(selected = isSelected, role = Role.Tab, onClick = { onSelect(item) })
                        .padding(horizontal = 16.dp)
                        .testTag("tab-${item.name}"),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    AnimatedNavIcon(item, isSelected, content)
                    Text(
                        stringResource(item.title),
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = if (isSelected) FontWeight.SemiBold else FontWeight.Medium,
                        color = content,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }
        }
    }
}

@Composable
private fun PanelContent(
    actions: MainActions,
    onLocate: (String) -> Unit = actions.locate,
    modifier: Modifier = Modifier,
) {
    AnimatedContent(
        targetState = actions.destination,
        modifier = modifier.fillMaxSize(),
        transitionSpec = {
            // M3 shared-axis (X) transition: direction follows the tab order.
            val direction = if (targetState.ordinal > initialState.ordinal) 1 else -1
            (slideInHorizontally(tween(320, easing = FastOutSlowInEasing)) { direction * it / 6 } +
                fadeIn(tween(210, delayMillis = 90, easing = LinearOutSlowInEasing))) togetherWith
                (slideOutHorizontally(tween(320, easing = FastOutSlowInEasing)) { -direction * it / 6 } +
                    fadeOut(tween(90, easing = FastOutLinearInEasing)))
        },
        label = "tab-content",
    ) { destination ->
      actions.panelState.SaveableStateProvider("panel-${destination.name}") {
        Box(Modifier.fillMaxSize()) {
            when (destination) {
                Destination.Overview -> if (actions.state.loadError) {
                    val locale = currentLocale()
                    Column(Modifier.padding(20.dp).testTag("content-Overview")) {
                        ErrorText(stringResource(R.string.entry_data_error))
                        TextButton(onClick = { actions.state.ensureCountries(locale) }) { Text(stringResource(R.string.retry)) }
                    }
                } else {
                    OverviewTab(actions.state, onOpenPolicy = actions.openPolicy, onLocate = onLocate,
                        onAddVisit = actions.addVisit, onWishlist = { code ->
                            if (actions.state.data.plannedTripRecords.any { it.countryCode == code }) actions.reviewWishlist(code)
                            else actions.addWishlist(code)
                        })
                }
                Destination.Visas -> MyVisasTab(actions.state, actions.retainVisaDraft)
                Destination.Travels -> TravelsTab(actions.state)
            }
        }
      }
    }
}

/**
 * Destination icon that plays a short, characterful motion when its tab becomes selected:
 * the globe spins, the visa card pops, and the plane flies off and lands again.
 */
@Composable
private fun AnimatedNavIcon(item: Destination, selected: Boolean, tint: Color, modifier: Modifier = Modifier) {
    val rotation = remember { Animatable(0f) }
    val scale = remember { Animatable(1f) }
    val travel = remember { Animatable(0f) }
    val alpha = remember { Animatable(1f) }
    var wasSelected by remember { mutableStateOf(selected) }
    LaunchedEffect(selected) {
        val play = selected && !wasSelected
        wasSelected = selected
        if (!play) {
            rotation.snapTo(0f); scale.snapTo(1f); travel.snapTo(0f); alpha.snapTo(1f)
            return@LaunchedEffect
        }
        when (item) {
            Destination.Overview -> {
                rotation.snapTo(0f)
                rotation.animateTo(360f, tween(900, easing = FastOutSlowInEasing))
                rotation.snapTo(0f)
            }
            Destination.Visas -> {
                scale.animateTo(1.35f, spring(dampingRatio = Spring.DampingRatioNoBouncy, stiffness = Spring.StiffnessMedium))
                scale.animateTo(1f, spring(dampingRatio = Spring.DampingRatioMediumBouncy, stiffness = Spring.StiffnessLow))
            }
            Destination.Travels -> {
                coroutineScope {
                    launch { travel.animateTo(1f, tween(240, easing = FastOutLinearInEasing)) }
                    launch { alpha.animateTo(0f, tween(240, easing = FastOutLinearInEasing)) }
                }
                travel.snapTo(-1f)
                coroutineScope {
                    launch { travel.animateTo(0f, spring(dampingRatio = 0.7f, stiffness = Spring.StiffnessMediumLow)) }
                    launch { alpha.animateTo(1f, tween(180)) }
                }
            }
        }
    }
    AppIcon(
        item.icon,
        modifier.size(22.dp).graphicsLayer {
            rotationY = rotation.value
            cameraDistance = 12f * density
            scaleX = scale.value
            scaleY = scale.value
            val distance = 22.dp.toPx() * 1.4f
            translationX = travel.value * distance
            translationY = -travel.value * distance
            this.alpha = alpha.value
        },
        tint = tint,
    )
}
