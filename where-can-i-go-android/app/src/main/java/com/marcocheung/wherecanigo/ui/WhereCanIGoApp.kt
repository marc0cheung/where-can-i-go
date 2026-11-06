package com.marcocheung.wherecanigo.ui

import android.app.Activity
import androidx.activity.compose.BackHandler
import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.foundation.isSystemInDarkTheme
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
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.BottomSheetScaffold
import androidx.compose.material3.BottomSheetDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationRail
import androidx.compose.material3.NavigationRailItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SheetValue
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.rememberBottomSheetScaffoldState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.runtime.saveable.SaveableStateHolder
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.layout.onSizeChanged
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.collapse
import androidx.compose.ui.semantics.expand
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.core.view.WindowCompat
import com.marcocheung.wherecanigo.R
import kotlinx.coroutines.launch

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
                                icon = { AppIcon(item.icon) },
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
                Column(Modifier.fillMaxSize().testTag("compact-layout")) {
                    PhoneContent(actions, camera, categoryByCode, flyRequest, onCountrySelected, Modifier.weight(1f))
                    NavigationBar(
                        containerColor = MaterialTheme.colorScheme.surfaceContainer,
                        tonalElevation = 0.dp,
                        windowInsets = WindowInsets.navigationBars,
                    ) {
                        Destination.entries.forEach { item ->
                            NavigationBarItem(
                                modifier = Modifier.testTag("tab-${item.name}"),
                                selected = destination == item,
                                onClick = { onTab(item) },
                                icon = { AppIcon(item.icon) },
                                label = { Text(stringResource(item.title)) },
                            )
                        }
                    }
                }
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

private val PeekHeight = 172.dp

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun PhoneContent(
    actions: MainActions,
    camera: MapCamera,
    categoryByCode: Map<String, VisaCategory>,
    flyRequest: FlyRequest?,
    onCountrySelected: (MapCountry) -> Unit,
    modifier: Modifier = Modifier,
) {
    val state = rememberBottomSheetScaffoldState()
    val scope = rememberCoroutineScope()
    val density = LocalDensity.current
    var cardHeight by remember { mutableStateOf(140.dp) }
    val expanded = state.bottomSheetState.currentValue == SheetValue.Expanded
    val collapse: () -> Unit = { scope.launch { state.bottomSheetState.partialExpand() } }
    LaunchedEffect(actions.destination) {
        if (actions.destination == Destination.Travels) state.bottomSheetState.expand()
    }
    BackHandler(enabled = expanded && actions.selectedCode == null) { collapse() }
    BottomSheetScaffold(
        modifier = modifier.clipToBounds().testTag("bottom-sheet"),
        scaffoldState = state,
        sheetPeekHeight = PeekHeight,
        sheetContainerColor = MaterialTheme.colorScheme.surfaceContainer,
        sheetTonalElevation = 0.dp,
        sheetShadowElevation = 3.dp,
        sheetDragHandle = {
            BottomSheetDefaults.DragHandle(
                modifier = Modifier.testTag("sheet-handle").semantics {
                    if (expanded) {
                        collapse { collapse(); true }
                    } else {
                        expand {
                            scope.launch { state.bottomSheetState.expand() }
                            true
                        }
                    }
                },
            )
        },
        sheetContent = {
            SheetHeader(
                actions.state, actions.dice,
                onDicePicked = { actions.locate(it); collapse() },
                onOpenProfile = actions.openProfile,
                onOpenSettings = actions.openSettings,
            )
            PanelContent(actions, onLocate = { actions.locate(it); collapse() })
        },
    ) {
        WorldMap(
            camera,
            actions.selectedCode,
            categoryByCode,
            onCountrySelected,
            Modifier.fillMaxSize(),
            flyRequest = flyRequest,
            cameraBottomPadding = PeekHeight + cardHeight + 24.dp,
            visitedCodes = actions.state.data.visitedCountryCodes,
        ) {
            actions.selectedCode?.let { code ->
                SelectedCountryCard(
                    actions,
                    code,
                    Modifier.align(Alignment.BottomCenter).padding(start = 12.dp, end = 12.dp, bottom = PeekHeight + 12.dp)
                        .onSizeChanged { cardHeight = with(density) { it.height.toDp() } },
                )
            }
        }
    }
}

@Composable
private fun PanelContent(actions: MainActions, onLocate: (String) -> Unit = actions.locate) {
    actions.panelState.SaveableStateProvider("panel") {
        Box(Modifier.fillMaxSize()) {
            when (actions.destination) {
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
