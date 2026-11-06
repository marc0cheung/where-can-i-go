package com.marcocheung.wherecanigo.ui

import android.content.Context
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import android.util.AtomicFile
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import org.json.JSONObject
import com.marcocheung.wherecanigo.R
import java.io.File
import java.io.IOException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.time.LocalDate
import java.util.Locale

/** Port of iOS `AppState`; one instance per process so it survives configuration changes. */
class AppState private constructor(private val context: Context) {
    val appContext: Context get() = context
    var data by mutableStateOf(AppData("HKG", emptyList(), emptyList()))
        private set
    var needsPassportSelection by mutableStateOf(false)
        private set
    var bundledUpdatedAt by mutableStateOf<LocalDate?>(null)
        private set
    var countries by mutableStateOf<List<Country>>(emptyList())
        private set
    var countriesByCode by mutableStateOf<Map<String, Country>>(emptyMap())
        private set
    var airlines by mutableStateOf<List<Airline>?>(null)
        private set
    var pendingAddVisaCountryCode by mutableStateOf<String?>(null)
    var pendingAddVisitCountryCode by mutableStateOf<String?>(null)
    var pendingAddWishlistCountryCode by mutableStateOf<String?>(null)
    var pendingReviewWishlistCountryCode by mutableStateOf<String?>(null)
    var loadError by mutableStateOf(false)
        private set
    var dataLoadFailed by mutableStateOf(false)
        private set
    var operationError by mutableStateOf<Int?>(null)
        private set
    var profile by mutableStateOf(UserProfile())
        private set
    var profileLoadFailed by mutableStateOf(false)
        private set
    var searchEngine by mutableStateOf(SearchEngine.google)
        private set
    var referenceDate by mutableStateOf(LocalDate.now())
        private set
    private var countriesLocale: Locale? = null

    private val dataFile = File(context.filesDir, "app_data.json")
    private val storage = AtomicFile(dataFile)
    private var policyCache: Pair<String, BundledEntryPolicy>? = null

    init {
        loadSavedData()
        loadProfile()
        searchEngine = SearchEngine.entries.firstOrNull { it.name == context.getSharedPreferences("settings", Context.MODE_PRIVATE)
            .getString("searchEngine", null) } ?: SearchEngine.google
        airlines = runCatching { BundledRepository.loadAirlines(context) }
            .onFailure { Log.e("AppState", "Cannot load airline destinations", it) }.getOrNull()
    }

    fun loadSavedData() {
        try {
            LocalStore.recover(context.filesDir)
            if (dataFile.exists() || File(dataFile.path + ".bak").exists()) {
                data = AppData.fromJson(JSONObject(storage.openRead().bufferedReader().use { it.readText() }))
                needsPassportSelection = false
            } else {
                val bundled = policy("HKG") ?: run { dataLoadFailed = true; return }
                data = AppData("HKG", bundled.entries, emptyList())
                needsPassportSelection = true
            }

            bundledUpdatedAt = policy(data.passportCode)?.updatedAt
            dataLoadFailed = false
        } catch (failure: Exception) {
            Log.e("AppState", "Cannot read saved data; keeping the file unchanged", failure)
            dataLoadFailed = true
        }
    }

    fun loadProfile() {
        try {
            val file = File(context.filesDir, "user_profile.json")
            val loaded = if (file.exists()) UserProfile.fromJson(JSONObject(file.readText())) else UserProfile()
            loaded.photoData?.let { decodeProfilePhoto(it, 512).recycle() }
            profile = loaded
            profileLoadFailed = false
        } catch (failure: Exception) {
            profileLoadFailed = true
            reportError(R.string.profile_load_error, failure)
        }
    }

    fun saveProfile(draft: UserProfile, passportCode: String): Boolean {
        if (profileLoadFailed || dataLoadFailed) { operationError = R.string.profile_load_error; return false }
        val next = if (passportCode != data.passportCode) {
            val bundled = policy(passportCode) ?: return false
            data.copy(passportCode = passportCode, defaultVisas = bundled.entries)
        } else data
        return commitRestoredData(next, draft.copy(name = draft.name.trim()))
    }

    fun chooseSearchEngine(engine: SearchEngine) {
        if (context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit().putString("searchEngine", engine.name).commit())
            searchEngine = engine
        else operationError = R.string.save_data_error
    }

    fun commitRestoredData(next: AppData, nextProfile: UserProfile): Boolean {
        try {
            LocalStore.commit(context.filesDir, next.toJson(), nextProfile.toJson())
            data = next; profile = nextProfile
            bundledUpdatedAt = policy(next.passportCode)?.updatedAt
            needsPassportSelection = false
            return true
        } catch (failure: Exception) {
            reportError(R.string.save_data_error, failure)
            if (File(context.filesDir, "data_transaction.json").exists()) dataLoadFailed = true
            return false
        }
    }

    fun ensureCountries(locale: Locale) {
        if (countriesLocale == locale) return
        runCatching { BundledRepository.loadCountries(context, locale) }
            .onSuccess { list ->
                countries = list
                countriesByCode = list.associateBy { it.code }
                countriesLocale = locale
                loadError = false
            }
            .onFailure { Log.e("AppState", "Cannot load countries", it); loadError = true }
    }

    fun refreshReferenceDate() {
        referenceDate = LocalDate.now()
    }

    fun eligibility(code: String): VisaEligibility {
        val category = data.defaultVisas.firstOrNull { it.countryCode == code }?.category ?: VisaCategory.VisaRequired
        return VisaEligibility.evaluate(code, category, data.personalVisas, referenceDate)
    }

    fun completePassportSelection(code: String): Boolean {
        require(code in SupportedPassports)
        val bundled = policy(code) ?: return false
        if (!update(data.copy(passportCode = code, defaultVisas = bundled.entries))) return false
        bundledUpdatedAt = bundled.updatedAt
        needsPassportSelection = false
        return true
    }

    fun addPersonalVisa(visa: PersonalVisa) = update(data.copy(personalVisas = data.personalVisas + visa))

    fun saveVisit(visit: Visit) = update(data.copy(visits = data.visits.upserting(visit.id, visit.toJson())))
    fun savePlannedTrip(trip: PlannedTrip) = update(data.copy(plannedTrips = data.plannedTrips.upserting(trip.id, trip.toJson())))
    fun removeVisits(ids: Set<String>) = update(data.copy(visits = data.visits.removingIds(ids)))
    fun removePlans(ids: Set<String>) = update(data.copy(plannedTrips = data.plannedTrips.removingIds(ids)))
    fun completePlannedTrip(id: String, visit: Visit): Boolean {
        if (data.plannedTripRecords.none { it.id == id } || data.visitRecords.any { it.id == id }) {
            operationError = R.string.plan_unavailable
            return false
        }
        return update(data.copy(visits = data.visits.upserting(id, visit.copy(id = id).toJson()),
            plannedTrips = data.plannedTrips.removingIds(setOf(id))))
    }

    fun updatePersonalVisa(visa: PersonalVisa): Boolean {
        check(data.personalVisas.any { it.id == visa.id })
        if (!update(data.copy(personalVisas = data.personalVisas.map { if (it.id == visa.id) visa else it }))) return false
        pruneAttachments(visa.id, visa.attachmentFileNames)
        return true
    }

    fun removePersonalVisa(id: String): Boolean {
        if (!update(data.copy(personalVisas = data.personalVisas.filterNot { it.id == id }))) return false
        pruneAttachments(id, emptyList())
        return true
    }

    fun addDefaultVisa(entry: DefaultVisaEntry) =
        update(data.copy(defaultVisas = data.defaultVisas.filterNot { it.countryCode == entry.countryCode } + entry))

    fun removeDefaultVisa(code: String) =
        update(data.copy(defaultVisas = data.defaultVisas.filterNot { it.countryCode == code }))

    fun resetDefaultsToBundled(): Boolean {
        val bundled = policy(data.passportCode) ?: return false
        if (!update(data.copy(defaultVisas = bundled.entries))) return false
        bundledUpdatedAt = bundled.updatedAt
        return true
    }

    fun saveEntryPolicy(code: String, entry: DefaultVisaEntry?, visa: PersonalVisa?): Boolean {
        val next = data.copy(
            defaultVisas = data.defaultVisas.filterNot { it.countryCode == code } + listOfNotNull(entry),
            personalVisas = data.personalVisas.map { if (visa != null && it.id == visa.id) visa else it },
        )
        if (!update(next)) return false
        visa?.let { pruneAttachments(it.id, it.attachmentFileNames) }
        return true
    }

    fun bundledEntry(code: String): DefaultVisaEntry? =
        policy(data.passportCode)?.entries?.firstOrNull { it.countryCode == code }

    private fun policy(code: String): BundledEntryPolicy? =
        policyCache?.takeIf { it.first == code }?.second
            ?: runCatching { BundledRepository.loadPolicy(context, code) }
                .onFailure { reportError(R.string.entry_data_error, it) }
                .getOrNull()?.also { policyCache = code to it }

    private fun update(newData: AppData): Boolean {
        if (dataLoadFailed) {
            operationError = R.string.saved_data_error
            return false
        }
        val temp = File(dataFile.parentFile, "app_data.json.tmp")
        try {
            temp.outputStream().use {
                it.write(newData.toJson().toString(2).toByteArray(Charsets.UTF_8))
                it.fd.sync()
            }
            Files.move(temp.toPath(), dataFile.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (failure: Exception) {
            if (temp.exists() && !temp.delete()) Log.e("AppState", "Cannot remove incomplete data file")
            reportError(R.string.save_data_error, failure)
            return false
        }
        data = newData
        return true
    }

    fun pruneAttachments(visaId: String, retained: List<String>) {
        runCatching { VisaAttachmentStore.prune(context, visaId, retained.toSet()) }
            .onFailure { reportError(R.string.attachment_delete_error, it) }
    }

    fun reportError(message: Int, failure: Throwable) {
        Log.e("AppState", context.getString(message), failure)
        operationError = message
    }

    fun clearError() {
        operationError = null
    }

    fun searchCountry(name: String) {
        try {
            context.startActivity(Intent(Intent.ACTION_VIEW,
                Uri.parse(searchEngine.url).buildUpon().appendQueryParameter("q", name).build())
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        } catch (failure: ActivityNotFoundException) {
            reportError(R.string.browser_unavailable, failure)
        }
    }

    companion object {
        @Volatile
        private var instance: AppState? = null

        fun get(context: Context): AppState =
            instance ?: synchronized(this) {
                instance ?: AppState(context.applicationContext).also { instance = it }
            }
    }
}

/** Port of iOS `VisaAttachmentStore`: files live in `files/visa_attachments/<visaID>/`. */
object VisaAttachmentStore {
    private fun root(context: Context) = File(context.filesDir, "visa_attachments")

    fun folder(context: Context, visaId: String) = File(root(context), visaId)

    fun file(context: Context, fileName: String, visaId: String) = File(folder(context, visaId), fileName)

    fun save(context: Context, bytes: ByteArray, extension: String, visaId: String): String {
        val folder = folder(context, visaId)
        if (!folder.isDirectory && !folder.mkdirs()) throw IOException("Cannot create attachment folder")
        val name = "${PersonalVisa.newId()}.$extension"
        val file = File(folder, name)
        try {
            file.writeBytes(bytes)
        } catch (failure: IOException) {
            if (file.exists() && !file.delete()) Log.e("VisaAttachments", "Cannot remove incomplete attachment")
            throw failure
        }
        return name
    }

    fun delete(context: Context, fileName: String, visaId: String) {
        val file = file(context, fileName, visaId)
        if (file.exists() && !file.delete()) throw IOException("Cannot delete attachment")
    }

    fun deleteFolder(context: Context, visaId: String) {
        prune(context, visaId, emptySet())
    }

    fun prune(context: Context, visaId: String, retained: Set<String>) {
        val folder = folder(context, visaId)
        if (!folder.exists()) return
        val files = folder.listFiles() ?: throw IOException("Cannot list attachment folder")
        files.filterNot { it.name in retained }.forEach {
            if (!it.delete()) throw IOException("Cannot delete attachment")
        }
        if (folder.listFiles()?.isEmpty() == true && !folder.delete()) throw IOException("Cannot delete empty attachment folder")
    }
}
