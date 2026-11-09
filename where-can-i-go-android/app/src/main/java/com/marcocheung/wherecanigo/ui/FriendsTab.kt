package com.marcocheung.wherecanigo.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.BackHandler
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.marcocheung.wherecanigo.R
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.IOException

@Composable
internal fun FriendsTab(state: AppState, onSelectSegment: (Boolean?) -> Unit) {
    BackHandler(onBack = { onSelectSegment(false) })
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    var sharing by remember { mutableStateOf(false) }
    var identity by remember { mutableStateOf(false) }
    var incoming by remember { mutableStateOf<Pair<VerifiedTravelCard, String?>?>(null) }
    var detail by remember { mutableStateOf<TravelCardFriend?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null) {
            scope.launch {
                try {
                    val bytes = withContext(Dispatchers.IO) {
                        context.contentResolver.openInputStream(uri)?.use(::readTravelCard)
                            ?: throw IOException("Cannot read travel card")
                    }
                    val card = TravelCardCrypto.decodeAndVerify(bytes)
                    val ownID = SharingIdentity.current(context)?.let { TravelCardCrypto.sharerID(it.publicKey) }
                    incoming = card to ownID
                } catch (cancelled: kotlinx.coroutines.CancellationException) {
                    throw cancelled
                } catch (failure: Exception) {
                    error = failure.localizedMessage ?: context.getString(R.string.travel_card_invalid)
                }
            }
        }
    }

    LaunchedEffect(state.incomingTravelCard) {
        val uri = state.incomingTravelCard ?: return@LaunchedEffect
        state.incomingTravelCard = null
        try {
            val bytes = withContext(Dispatchers.IO) {
                context.contentResolver.openInputStream(uri)?.use(::readTravelCard)
                    ?: throw IOException("Cannot read travel card")
            }
            val card = TravelCardCrypto.decodeAndVerify(bytes)
            val ownID = SharingIdentity.current(context)?.let { TravelCardCrypto.sharerID(it.publicKey) }
            incoming = card to ownID
        } catch (cancelled: kotlinx.coroutines.CancellationException) {
            throw cancelled
        } catch (failure: Exception) {
            error = failure.localizedMessage ?: context.getString(R.string.travel_card_invalid)
        }
    }

    LazyColumn(
        Modifier.fillMaxSize().testTag("content-Friends"),
        contentPadding = androidx.compose.foundation.layout.PaddingValues(
            start = 16.dp, end = 16.dp, top = 8.dp, bottom = LocalSheetBottomPadding.current + 16.dp,
        ),
        verticalArrangement = Arrangement.spacedBy(GroupedListGap),
    ) {
        item {
            Column(Modifier.padding(bottom = 12.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                TravelSegments(wishlist = false, friends = true, onSelect = onSelectSegment)
                Text(stringResource(R.string.friends), style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold)
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Button(onClick = { sharing = true }, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp)
                        .testTag("share-travel-card")) {
                        Text(stringResource(R.string.share_my_travel_card))
                    }
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedButton(onClick = {
                            picker.launch(arrayOf("application/vnd.com.marcocheung.wherecanigo.travelcard",
                                "application/json", "text/plain", "application/octet-stream"))
                        }, modifier = Modifier.weight(1f).heightIn(min = 48.dp).testTag("add-travel-card")) {
                            Text(stringResource(R.string.add_friend), maxLines = 1)
                        }
                        OutlinedButton(onClick = { identity = true }, modifier = Modifier.weight(1f).heightIn(min = 48.dp)) {
                            Text(stringResource(R.string.sharing_identity), maxLines = 1)
                        }
                    }
                }
            }
        }
        if (state.friendStore.loadFailed) {
            item {
                Text(stringResource(R.string.friends_load_error), color = MaterialTheme.colorScheme.error)
                OutlinedButton(onClick = state.friendStore::load) { Text(stringResource(R.string.retry)) }
            }
        } else if (state.friendStore.friends.isEmpty()) {
            item {
                EmptyState(R.drawable.ic_person, stringResource(R.string.no_friends), stringResource(R.string.friends_offline_hint))
            }
        } else {
            val friends = state.friendStore.friends.sortedBy { it.name.lowercase() }
            itemsIndexed(friends, key = { _, friend -> friend.sharerID }) { index, friend ->
                Surface(
                    onClick = { detail = friend },
                    shape = groupedShape(index, friends.size),
                    color = listItemColor(),
                    modifier = Modifier.fillMaxWidth().testTag("friend-${friend.sharerID}"),
                ) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Text(friend.name, fontWeight = FontWeight.SemiBold)
                        Text(stringResource(R.string.friend_updated, friend.lastReceivedAt.toString()),
                            style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                        Text(stringResource(R.string.friend_card_counts,
                            friend.card.been?.size ?: 0, friend.card.wishlist?.size ?: 0),
                            style = MaterialTheme.typography.bodySmall)
                    }
                }
            }
        }
    }

    if (sharing) TravelCardOptionsDialog(state, { sharing = false })
    if (identity) SharingIdentityDialog(state, onDismiss = { identity = false })
    incoming?.let { (card, ownID) ->
        ReceiveTravelCardDialog(state, card, ownID, onDismiss = { incoming = null }, onError = { error = it })
    }
    detail?.let { friend ->
        FriendDetailsDialog(state, friend, onDismiss = { detail = null }, onError = { error = it })
    }
    error?.let { message ->
        AlertDialog(onDismissRequest = { error = null }, title = { Text(stringResource(R.string.travel_card_error_title)) },
            text = { Text(message) }, confirmButton = { TextButton(onClick = { error = null }) { Text(stringResource(R.string.ok)) } })
    }
}

@Composable
private fun TravelCardOptionsDialog(state: AppState, onDismiss: () -> Unit) {
    val context = LocalContext.current
    var options by remember { mutableStateOf(SharingOptions.load(context)) }
    var rememberAsDefault by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.share_my_travel_card)) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(options.displayName, { options = options.copy(displayName = it.take(60)) },
                    label = { Text(stringResource(R.string.display_name)) }, singleLine = true)
                Text(stringResource(R.string.travel_card_kept_private), style = MaterialTheme.typography.bodySmall)
                ShareOption(stringResource(R.string.include_photo), options.includePhoto,
                    enabled = state.profile.photoData != null) {
                    options = options.copy(includePhoto = it)
                }
                ShareCategory(stringResource(R.string.share_been), options.includeBeen, options.beenFields,
                    { options = options.copy(includeBeen = it) }, { options = options.copy(beenFields = it) })
                ShareCategory(stringResource(R.string.share_wishlist), options.includeWishlist, options.wishlistFields,
                    { options = options.copy(includeWishlist = it) }, { options = options.copy(wishlistFields = it) })
                ShareOption(stringResource(R.string.remember_as_default), rememberAsDefault) { rememberAsDefault = it }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                try {
                    if (rememberAsDefault) SharingOptions.save(context, options)
                    val file = TravelCardBuilder.create(context, options, state.profile, state.data)
                    context.startActivity(TravelCardBuilder.shareIntent(context, file))
                    onDismiss()
                } catch (failure: Exception) {
                    error = failure.localizedMessage ?: context.getString(R.string.travel_card_create_error)
                }
            }, enabled = options.displayName.trim().isNotEmpty() || state.profile.name.isNotBlank()) {
                Text(stringResource(R.string.share))
            }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun ShareOption(label: String, checked: Boolean, enabled: Boolean = true, onChecked: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Checkbox(checked, onCheckedChange = onChecked, enabled = enabled)
        Text(label, Modifier.padding(start = 4.dp))
    }
}

@Composable
private fun ShareCategory(
    title: String,
    checked: Boolean,
    fields: TravelCardFields,
    onChecked: (Boolean) -> Unit,
    onFields: (TravelCardFields) -> Unit,
) {
    Column {
        ShareOption(title, checked, onChecked = onChecked)
        if (checked) Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            listOf(
                R.string.share_dates to fields.dates,
                R.string.share_length to fields.length,
                R.string.share_location to fields.location,
                R.string.share_purpose to fields.purpose,
            ).forEach { (label, value) ->
                FilterChip(value, onClick = {
                    val next = when (label) {
                        R.string.share_dates -> fields.copy(dates = !value)
                        R.string.share_length -> fields.copy(length = !value)
                        R.string.share_location -> fields.copy(location = !value)
                        else -> fields.copy(purpose = !value)
                    }
                    onFields(next)
                }, label = { Text(stringResource(label), style = MaterialTheme.typography.labelSmall) })
            }
        }
    }
}

@Composable
private fun ReceiveTravelCardDialog(
    state: AppState,
    card: VerifiedTravelCard,
    ownID: String?,
    onDismiss: () -> Unit,
    onError: (String) -> Unit,
) {
    val receipt = remember(card, ownID) { state.friendStore.receipt(card, ownID) }
    var replace by remember { mutableStateOf<TravelCardFriend?>(null) }
    var saved by remember { mutableStateOf<TravelCardFriend?>(null) }
    val sameName = (receipt as? TravelCardReceipt.New)?.sameName.orEmpty()
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(saved?.let { stringResource(R.string.friend_added, it.name) } ?: card.payload.displayName) },
        text = {
            Column(Modifier.verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stringResource(R.string.safety_code, TravelCardCrypto.safetyCode(card.publicKey)))
                Text(stringResource(R.string.travel_card_created, card.payload.createdAt))
                Text(stringResource(R.string.friend_card_counts, card.payload.been?.size ?: 0, card.payload.wishlist?.size ?: 0))
                when (receipt) {
                    TravelCardReceipt.OwnCard -> Text(stringResource(R.string.own_travel_card))
                    is TravelCardReceipt.Unchanged -> Text(stringResource(R.string.card_unchanged, receipt.existing.name))
                    is TravelCardReceipt.Older -> Text(stringResource(R.string.card_is_older, receipt.existing.name))
                    is TravelCardReceipt.Update -> Text(stringResource(R.string.card_update_prompt, receipt.existing.name))
                    is TravelCardReceipt.New -> {
                        Text(stringResource(R.string.card_includes))
                        if (sameName.isNotEmpty()) Text(stringResource(R.string.same_name_warning))
                    }
                }
                sameName.forEach { friend ->
                    OutlinedButton(onClick = { replace = friend }, modifier = Modifier.fillMaxWidth()) {
                        Text(stringResource(R.string.replace_friend, friend.name))
                    }
                }
            }
        },
        confirmButton = {
            val label = when {
                saved != null -> stringResource(R.string.done)
                receipt == TravelCardReceipt.OwnCard -> stringResource(R.string.done)
                receipt is TravelCardReceipt.Unchanged -> stringResource(R.string.done)
                receipt is TravelCardReceipt.Older -> stringResource(R.string.done)
                receipt is TravelCardReceipt.Update -> stringResource(R.string.update_friend)
                else -> stringResource(R.string.add_friend)
            }
            TextButton(onClick = {
                if (saved != null || receipt == TravelCardReceipt.OwnCard ||
                    receipt is TravelCardReceipt.Unchanged || receipt is TravelCardReceipt.Older) onDismiss()
                else try {
                    saved = state.friendStore.save(card)
                } catch (failure: Exception) { onError(failure.localizedMessage ?: "Couldn't save friend") }
            }) { Text(label) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
    replace?.let { friend ->
        AlertDialog(
            onDismissRequest = { replace = null },
            title = { Text(stringResource(R.string.replace_friend, friend.name)) },
            text = { Text(stringResource(R.string.replace_friend_warning, friend.name,
                TravelCardCrypto.safetyCode(card.publicKey))) },
            confirmButton = {
                TextButton(onClick = {
                    try { saved = state.friendStore.save(card, friend.sharerID) }
                    catch (failure: Exception) { onError(failure.localizedMessage ?: "Couldn't save friend") }
                    replace = null
                }) { Text(stringResource(R.string.replace)) }
            },
            dismissButton = { TextButton(onClick = { replace = null }) { Text(stringResource(R.string.cancel)) } },
        )
    }
}

@Composable
private fun FriendDetailsDialog(state: AppState, friend: TravelCardFriend, onDismiss: () -> Unit, onError: (String) -> Unit) {
    var nickname by remember(friend.sharerID) { mutableStateOf(friend.nickname.orEmpty()) }
    var confirmRemove by remember { mutableStateOf(false) }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(friend.name) },
        text = {
            LazyColumn(
                modifier = Modifier.heightIn(max = 480.dp),
                contentPadding = PaddingValues(vertical = 4.dp),
                verticalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                item {
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(nickname, { nickname = it.take(60) },
                            label = { Text(stringResource(R.string.nickname)) })
                        Text(stringResource(R.string.safety_code, friend.safetyCode))
                        Text(stringResource(R.string.friend_data_offline))
                    }
                }
                friend.card.been?.let { records ->
                    item { Text(stringResource(R.string.share_been), style = MaterialTheme.typography.titleMedium) }
                    items(records) { record -> TravelCardRecordRow(state, record) }
                }
                friend.card.wishlist?.let { records ->
                    item { Text(stringResource(R.string.share_wishlist), style = MaterialTheme.typography.titleMedium) }
                    items(records) { record -> TravelCardRecordRow(state, record) }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                try { state.friendStore.rename(friend.sharerID, nickname); onDismiss() }
                catch (failure: Exception) { onError(failure.localizedMessage ?: "Couldn't save friend") }
            }) { Text(stringResource(R.string.save)) }
        },
        dismissButton = {
            Row {
                TextButton(onClick = { confirmRemove = true }) { Text(stringResource(R.string.remove_friend)) }
                TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
            }
        },
    )
    if (confirmRemove) AlertDialog(
        onDismissRequest = { confirmRemove = false },
        title = { Text(stringResource(R.string.remove_friend_title, friend.name)) },
        text = { Text(stringResource(R.string.remove_friend_body)) },
        confirmButton = {
            TextButton(onClick = {
                try { state.friendStore.remove(friend.sharerID); confirmRemove = false; onDismiss() }
                catch (failure: Exception) { onError(failure.localizedMessage ?: "Couldn't remove friend") }
            }) { Text(stringResource(R.string.remove_friend)) }
        },
        dismissButton = { TextButton(onClick = { confirmRemove = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun SharingIdentityDialog(state: AppState, onDismiss: () -> Unit) {
    var identity by remember { mutableStateOf<SigningIdentity?>(null) }
    var confirmReset by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(state.appContext) {
        try {
            identity = SharingIdentity.current(state.appContext)
        } catch (failure: Exception) {
            error = failure.localizedMessage ?: state.appContext.getString(R.string.identity_access_error)
        }
    }
    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.sharing_identity)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                if (identity == null) Text(stringResource(R.string.identity_not_created))
                else {
                    Text(stringResource(R.string.safety_code,
                        TravelCardCrypto.safetyCode(requireNotNull(identity).publicKey)))
                    Text(stringResource(R.string.identity_explanation))
                }
                if (identity != null || error != null)
                    TextButton(onClick = { confirmReset = true }) { Text(stringResource(R.string.reset_safety_code)) }
                error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            }
        },
        confirmButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.done)) } },
    )
    if (confirmReset) AlertDialog(
        onDismissRequest = { confirmReset = false },
        title = { Text(stringResource(R.string.reset_safety_code)) },
        text = { Text(stringResource(R.string.reset_identity_warning)) },
        confirmButton = {
            TextButton(onClick = {
                try {
                    SharingIdentity.reset(state.appContext)
                    identity = null
                    error = null
                    confirmReset = false
                }
                catch (failure: Exception) { error = failure.localizedMessage ?: "Couldn't reset identity" }
            }) { Text(stringResource(R.string.reset)) }
        },
        dismissButton = { TextButton(onClick = { confirmReset = false }) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun TravelCardRecordRow(state: AppState, record: TravelCardRecord) {
    val country = state.countriesByCode[record.countryCode]
    Column(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        Text(country?.localizedName(currentLocale()) ?: record.countryCode, fontWeight = FontWeight.SemiBold)
        val dates = listOfNotNull(record.startDate, record.endDate).distinct()
        if (dates.isNotEmpty()) Text(dates.joinToString(" – "), style = MaterialTheme.typography.bodySmall)
        record.days?.let { Text(stringResource(R.string.shared_days, it), style = MaterialTheme.typography.bodySmall) }
        record.location?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
        record.purpose?.let { purpose ->
            VisitPurpose.entries.firstOrNull { it.name == purpose }?.let {
                Text(stringResource(it.label), style = MaterialTheme.typography.bodySmall)
            }
        }
    }
}

private fun readTravelCard(input: java.io.InputStream): ByteArray {
    val output = ByteArrayOutputStream()
    val buffer = ByteArray(8192)
    while (true) {
        val count = input.read(buffer)
        if (count < 0) break
        if (output.size() + count > 4 * 1024 * 1024) throw IOException("Travel card is too large")
        output.write(buffer, 0, count)
    }
    return output.toByteArray()
}
