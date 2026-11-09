package com.marcocheung.wherecanigo.ui

import android.content.Context
import android.content.Intent
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.IOException
import java.math.BigInteger
import java.nio.charset.StandardCharsets
import java.security.AlgorithmParameters
import java.security.KeyFactory
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import java.security.spec.ECParameterSpec
import java.security.spec.ECPrivateKeySpec
import java.security.spec.ECPublicKeySpec
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

internal data class TravelCardFields(
    val dates: Boolean = false,
    val length: Boolean = false,
    val location: Boolean = false,
    val purpose: Boolean = false,
) {
    fun toJson() = JSONObject().put("dates", dates).put("length", length)
        .put("location", location).put("purpose", purpose)

    companion object {
        fun fromJson(json: JSONObject) = TravelCardFields(
            json.optBoolean("dates"), json.optBoolean("length"),
            json.optBoolean("location"), json.optBoolean("purpose"),
        )
    }
}

internal data class SharingOptions(
    val displayName: String = "",
    val includePhoto: Boolean = false,
    val includeBeen: Boolean = false,
    val beenFields: TravelCardFields = TravelCardFields(),
    val includeWishlist: Boolean = false,
    val wishlistFields: TravelCardFields = TravelCardFields(),
) {
    fun toJson() = JSONObject().put("displayName", displayName).put("includePhoto", includePhoto)
        .put("includeBeen", includeBeen).put("beenFields", beenFields.toJson())
        .put("includeWishlist", includeWishlist).put("wishlistFields", wishlistFields.toJson())

    companion object {
        private const val KEY = "sharing.defaults"
        fun load(context: Context): SharingOptions = runCatching {
            val raw = context.getSharedPreferences("settings", Context.MODE_PRIVATE).getString(KEY, null)
                ?: return SharingOptions()
            val json = JSONObject(raw)
            SharingOptions(
                json.optString("displayName"), json.optBoolean("includePhoto"), json.optBoolean("includeBeen"),
                json.optJSONObject("beenFields")?.let(TravelCardFields::fromJson) ?: TravelCardFields(),
                json.optBoolean("includeWishlist"),
                json.optJSONObject("wishlistFields")?.let(TravelCardFields::fromJson) ?: TravelCardFields(),
            )
        }.getOrElse { SharingOptions() }

        fun save(context: Context, options: SharingOptions) {
            check(context.getSharedPreferences("settings", Context.MODE_PRIVATE).edit()
                .putString(KEY, options.toJson().toString()).commit()) { "Cannot save sharing defaults" }
        }
    }
}

internal data class TravelCardRecord(
    val countryCode: String,
    val startDate: String? = null,
    val endDate: String? = null,
    val days: Int? = null,
    val location: String? = null,
    val purpose: String? = null,
) {
    fun toJson() = JSONObject().put("countryCode", countryCode).apply {
        putNullable("startDate", startDate); putNullable("endDate", endDate)
        if (days != null) put("days", days)
        putNullable("location", location); putNullable("purpose", purpose)
    }

    companion object {
        fun fromJson(json: JSONObject) = TravelCardRecord(
            json.getString("countryCode"), json.optNullable("startDate"), json.optNullable("endDate"),
            if (json.has("days") && !json.isNull("days")) json.getInt("days") else null,
            json.optNullable("location"), json.optNullable("purpose"),
        )
    }
}

internal data class TravelCardPayload(
    val sharerID: String,
    val cardRevision: Long,
    val createdAt: String,
    val displayName: String,
    val photo: ByteArray?,
    val been: List<TravelCardRecord>?,
    val wishlist: List<TravelCardRecord>?,
    val sharedPhoto: Boolean,
    val sharedBeen: TravelCardFields?,
    val sharedWishlist: TravelCardFields?,
) {
    fun toJson() = JSONObject().put("sharerID", sharerID).put("cardRevision", cardRevision)
        .put("createdAt", createdAt).put("displayName", displayName)
        .putNullable("photo", photo?.let { Base64.encodeToString(it, Base64.NO_WRAP) })
        .putNullable("been", been?.let { JSONArray(it.map(TravelCardRecord::toJson)) })
        .putNullable("wishlist", wishlist?.let { JSONArray(it.map(TravelCardRecord::toJson)) })
        .put("shared", JSONObject().put("photo", sharedPhoto)
            .putNullable("been", sharedBeen?.toJson()).putNullable("wishlist", sharedWishlist?.toJson()))

    fun validate(reencodePhoto: Boolean = false): TravelCardPayload {
        require(sharerID.matches(Regex("[0-9a-f]{64}")) && cardRevision > 0)
        Instant.parse(createdAt)
        val name = displayName.trim()
        require(name.isNotEmpty() && name.length <= 60)
        require((been?.size ?: 0) <= 5_000 && (wishlist?.size ?: 0) <= 2_000)
        (been.orEmpty() + wishlist.orEmpty()).forEach { record ->
            require(record.countryCode.matches(Regex("[A-Z]{3}")))
            val start = record.startDate?.let(LocalDate::parse)
            val end = record.endDate?.let(LocalDate::parse)
            require(start == null || end == null || !end.isBefore(start))
            require(record.days == null || record.days in 1..36_500)
            require(record.location == null || record.location.length <= 200)
        }
        val photoData = if (sharedPhoto) photo else null
        require(photoData == null || photoData.size <= 1024 * 1024)
        val cleanedPhoto = if (reencodePhoto && photoData != null) prepareProfilePhoto(photoData, 512) else photoData
        return copy(displayName = name, photo = cleanedPhoto,
            been = if (sharedBeen == null) null else been.orEmpty(),
            wishlist = if (sharedWishlist == null) null else wishlist.orEmpty())
    }

    companion object {
        fun fromJson(json: JSONObject): TravelCardPayload {
            val shared = json.getJSONObject("shared")
            fun records(name: String) = json.optJSONArray(name)?.let { array ->
                List(array.length()) { TravelCardRecord.fromJson(array.getJSONObject(it)) }
            }
            return TravelCardPayload(
                json.getString("sharerID"), json.getLong("cardRevision"), json.getString("createdAt"),
                json.getString("displayName"),
                json.optNullable("photo")?.let { Base64.decode(it, Base64.DEFAULT) },
                records("been"), records("wishlist"), shared.getBoolean("photo"),
                shared.optJSONObject("been")?.let(TravelCardFields::fromJson),
                shared.optJSONObject("wishlist")?.let(TravelCardFields::fromJson),
            )
        }
    }
}

internal data class VerifiedTravelCard(val publicKey: ByteArray, val payload: TravelCardPayload) {
    val sharerID get() = payload.sharerID
}

internal data class TravelCardFriend(
    val sharerID: String,
    val publicKey: ByteArray,
    val nickname: String?,
    val addedAt: Instant,
    val lastReceivedAt: Instant,
    val card: TravelCardPayload,
) {
    val name get() = nickname?.trim()?.takeIf(String::isNotEmpty) ?: card.displayName
    val safetyCode get() = TravelCardCrypto.safetyCode(publicKey)

    fun toJson() = JSONObject().put("sharerID", sharerID)
        .put("publicKey", Base64.encodeToString(publicKey, Base64.NO_WRAP))
        .putNullable("nickname", nickname).put("addedAt", addedAt.toString())
        .put("lastReceivedAt", lastReceivedAt.toString()).put("card", card.toJson())

    companion object {
        fun fromJson(json: JSONObject): TravelCardFriend {
            val key = Base64.decode(json.getString("publicKey"), Base64.DEFAULT)
            val id = json.getString("sharerID")
            val card = TravelCardPayload.fromJson(json.getJSONObject("card")).validate()
            require(key.size == 64 && TravelCardCrypto.sharerID(key) == id && card.sharerID == id)
            return TravelCardFriend(id, key, json.optNullable("nickname")?.trim()?.take(60)?.takeIf(String::isNotEmpty),
                Instant.parse(json.getString("addedAt")), Instant.parse(json.getString("lastReceivedAt")), card)
        }
    }
}

internal sealed interface TravelCardReceipt {
    data object OwnCard : TravelCardReceipt
    data class New(val sameName: List<TravelCardFriend>) : TravelCardReceipt
    data class Update(val existing: TravelCardFriend) : TravelCardReceipt
    data class Unchanged(val existing: TravelCardFriend) : TravelCardReceipt
    data class Older(val existing: TravelCardFriend) : TravelCardReceipt
}

internal object TravelCardCrypto {
    private val params: ECParameterSpec by lazy {
        AlgorithmParameters.getInstance("EC").apply { init(ECGenParameterSpec("secp256r1")) }
            .getParameterSpec(ECParameterSpec::class.java)
    }

    fun sharerID(publicKey: ByteArray) = MessageDigest.getInstance("SHA-256").digest(publicKey)
        .joinToString("") { "%02x".format(it.toInt() and 0xff) }

    fun safetyCode(publicKey: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest("wcig-safety".toByteArray() + publicKey)
        val number = BigInteger(1, digest.copyOfRange(0, 8)).mod(BigInteger("1000000000000"))
        val digits = number.toString().padStart(12, '0')
        return "${digits.substring(0, 4)} ${digits.substring(4, 8)} ${digits.substring(8)}"
    }

    fun publicKeyBytes(encoded: ByteArray): ByteArray {
        val key = KeyFactory.getInstance("EC").generatePublic(java.security.spec.X509EncodedKeySpec(encoded))
            as java.security.interfaces.ECPublicKey
        return fixed(key.w.affineX, 32) + fixed(key.w.affineY, 32)
    }

    private fun publicKey(raw: ByteArray) = KeyFactory.getInstance("EC").generatePublic(
        ECPublicKeySpec(java.security.spec.ECPoint(BigInteger(1, raw.copyOfRange(0, 32)),
            BigInteger(1, raw.copyOfRange(32, 64))), params))

    fun publicKeyFromPrivate(raw: ByteArray): ByteArray {
        require(raw.size == 32)
        val scalar = BigInteger(1, raw)
        require(scalar.signum() > 0 && scalar < params.order)
        val curve = params.curve
        val prime = (curve.field as java.security.spec.ECFieldFp).p
        fun mod(value: BigInteger) = value.mod(prime)
        fun add(left: java.security.spec.ECPoint?, right: java.security.spec.ECPoint?): java.security.spec.ECPoint? {
            if (left == null) return right
            if (right == null) return left
            val x1 = left.affineX; val y1 = left.affineY
            val x2 = right.affineX; val y2 = right.affineY
            if (x1 == x2 && mod(y1 + y2) == BigInteger.ZERO) return null
            val slope = if (x1 == x2 && y1 == y2) {
                mod(BigInteger.valueOf(3) * x1 * x1 + curve.a)
                    .multiply(mod(BigInteger.valueOf(2) * y1).modInverse(prime)).mod(prime)
            } else {
                mod(y2 - y1).multiply(mod(x2 - x1).modInverse(prime)).mod(prime)
            }
            val x3 = mod(slope * slope - x1 - x2)
            return java.security.spec.ECPoint(x3, mod(slope * (x1 - x3) - y1))
        }
        var result: java.security.spec.ECPoint? = null
        var addend: java.security.spec.ECPoint? = params.generator
        var remaining = scalar
        while (remaining.signum() > 0) {
            if (remaining.testBit(0)) result = add(result, addend)
            addend = add(addend, addend)
            remaining = remaining.shiftRight(1)
        }
        val point = requireNotNull(result)
        return fixed(point.affineX, 32) + fixed(point.affineY, 32)
    }

    fun verify(rawPublic: ByteArray, message: ByteArray, rawSignature: ByteArray): Boolean {
        if (rawPublic.size != 64 || rawSignature.size != 64) return false
        return runCatching {
            Signature.getInstance("SHA256withECDSA").run {
                initVerify(publicKey(rawPublic)); update(message); verify(rawToDer(rawSignature))
            }
        }.getOrDefault(false)
    }

    private fun fixed(value: BigInteger, size: Int): ByteArray {
        val bytes = value.toByteArray().let { if (it.size > size && it[0] == 0.toByte()) it.copyOfRange(1, it.size) else it }
        require(bytes.size <= size)
        return ByteArray(size - bytes.size) + bytes
    }

    private fun rawToDer(raw: ByteArray): ByteArray {
        fun integer(part: ByteArray): ByteArray {
            var first = 0
            while (first < part.lastIndex && part[first] == 0.toByte()) first++
            val value = part.copyOfRange(first, part.size).let { if (it[0].toInt() < 0) byteArrayOf(0) + it else it }
            return byteArrayOf(2, value.size.toByte()) + value
        }
        val body = integer(raw.copyOfRange(0, 32)) + integer(raw.copyOfRange(32, 64))
        return byteArrayOf(0x30, body.size.toByte()) + body
    }

    private fun derToRaw(der: ByteArray): ByteArray {
        var index = 2
        fun readInteger(): ByteArray {
            require(der[index++].toInt() == 2)
            val length = der[index++].toInt() and 0xff
            require(length in 1..33 && index + length <= der.size)
            val value = der.copyOfRange(index, index + length).also { index += length }
                .let { if (it.size == 33) { require(it[0] == 0.toByte()); it.copyOfRange(1, 33) } else it }
            require(value.size <= 32)
            return ByteArray(32 - value.size) + value
        }
        require(der.size >= 8 && der[0].toInt() == 0x30 && (der[1].toInt() and 0xff) == der.size - 2)
        val r = readInteger(); val s = readInteger()
        require(index == der.size)
        return r + s
    }

    fun decodeAndVerify(bytes: ByteArray): VerifiedTravelCard {
        require(bytes.size <= 4 * 1024 * 1024) { "Travel card is too large" }
        val envelope = JSONObject(bytes.toString(StandardCharsets.UTF_8))
        require(envelope.optString("format") == "wherecanigo.travelcard") { "This file isn't a travel card" }
        val version = envelope.getInt("schemaVersion")
        require(version <= 1) { "Update the app to open this travel card" }
        require(version >= 1)
        val public = Base64.decode(envelope.getString("publicKey"), Base64.DEFAULT)
        val payloadBytes = Base64.decode(envelope.getString("payload"), Base64.DEFAULT)
        val signature = Base64.decode(envelope.getString("signature"), Base64.DEFAULT)
        require(public.size == 64 && verify(public, payloadBytes, signature)) { "Travel card signature is invalid" }
        val payload = TravelCardPayload.fromJson(JSONObject(payloadBytes.toString(StandardCharsets.UTF_8))).validate(true)
        require(payload.sharerID == sharerID(public)) { "Travel card identity is invalid" }
        return VerifiedTravelCard(public, payload)
    }

    fun encode(payload: TravelCardPayload, key: java.security.PrivateKey, publicKey: ByteArray): ByteArray {
        require(sharerID(publicKey) == payload.sharerID)
        val payloadBytes = payload.toJson().toString().toByteArray(StandardCharsets.UTF_8)
        val signer = Signature.getInstance("SHA256withECDSA").apply { initSign(key); update(payloadBytes) }
        val raw = derToRaw(signer.sign())
        return JSONObject().put("format", "wherecanigo.travelcard").put("schemaVersion", 1)
            .put("publicKey", Base64.encodeToString(publicKey, Base64.NO_WRAP))
            .put("payload", Base64.encodeToString(payloadBytes, Base64.NO_WRAP))
            .put("signature", Base64.encodeToString(raw, Base64.NO_WRAP)).toString(2).toByteArray()
    }
}

internal data class SigningIdentity(val privateKey: java.security.PrivateKey, val publicKey: ByteArray, val lastRevision: Long)

internal object SharingIdentity {
    private const val alias = "wherecanigo-sharing-key"
    private const val fileName = "sharing_identity.json"

    @Synchronized
    fun current(context: Context): SigningIdentity? = read(context)

    @Synchronized
    fun loadOrCreate(context: Context): SigningIdentity {
        read(context)?.let { return it }
        val pair = KeyPairGenerator.getInstance("EC").apply { initialize(ECGenParameterSpec("secp256r1")) }.generateKeyPair()
        return SigningIdentity(pair.private, TravelCardCrypto.publicKeyBytes(pair.public.encoded), 0).also { save(context, it) }
    }

    @Synchronized
    fun next(context: Context): SigningIdentity {
        val current = loadOrCreate(context)
        val revision = maxOf(current.lastRevision + 1, Instant.now().epochSecond)
        return current.copy(lastRevision = revision).also { save(context, it) }
    }

    @Synchronized
    fun export(context: Context): JSONObject? = read(context)?.let {
        JSONObject().put("privateKey", Base64.encodeToString(it.privateKeyBytes(), Base64.NO_WRAP))
            .put("lastRevision", it.lastRevision)
    }

    @Synchronized
    fun install(context: Context, record: JSONObject?) {
        if (record == null) return
        val raw = Base64.decode(record.getString("privateKey"), Base64.DEFAULT)
        require(raw.size == 32)
        val privateKey = KeyFactory.getInstance("EC").generatePrivate(ECPrivateKeySpec(BigInteger(1, raw), curveParams()))
        require(record.getLong("lastRevision") >= 0)
        val current = read(context)
        val revision = maxOf(record.getLong("lastRevision"), current?.lastRevision ?: 0)
        save(context, SigningIdentity(privateKey, TravelCardCrypto.publicKeyFromPrivate(raw), revision))
    }

    @Synchronized
    fun reset(context: Context) {
        File(context.filesDir, fileName).takeIf(File::exists)?.let { check(it.delete()) }
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (store.containsAlias(alias)) store.deleteEntry(alias)
    }

    private fun SigningIdentity.privateKeyBytes(): ByteArray =
        (privateKey as java.security.interfaces.ECPrivateKey).s.scalarBytes()

    private fun BigInteger.scalarBytes(): ByteArray {
        val raw = toByteArray().let { if (it.size == 33 && it[0] == 0.toByte()) it.copyOfRange(1, 33) else it }
        require(raw.size <= 32)
        return ByteArray(32 - raw.size) + raw
    }

    private fun curveParams(): ECParameterSpec = AlgorithmParameters.getInstance("EC").apply {
        init(ECGenParameterSpec("secp256r1"))
    }.getParameterSpec(ECParameterSpec::class.java)

    private fun encryptionKey(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(alias, null) as? SecretKey)?.let { return it }
        return KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setRandomizedEncryptionRequired(true).build())
            generateKey()
        }
    }

    private fun save(context: Context, identity: SigningIdentity) {
        val raw = identity.privateKeyBytes()
        val json = JSONObject().put("privateKey", Base64.encodeToString(raw, Base64.NO_WRAP))
            .put("publicKey", Base64.encodeToString(identity.publicKey, Base64.NO_WRAP))
            .put("lastRevision", identity.lastRevision).toString().toByteArray()
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, encryptionKey()) }
        val wrapper = JSONObject().put("iv", Base64.encodeToString(cipher.iv, Base64.NO_WRAP))
            .put("data", Base64.encodeToString(cipher.doFinal(json), Base64.NO_WRAP))
        writeAtomic(File(context.filesDir, fileName), wrapper.toString())
    }

    private fun read(context: Context): SigningIdentity? {
        val file = File(context.filesDir, fileName)
        if (!file.exists()) return null
        val wrapper = JSONObject(file.readText())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply {
            init(Cipher.DECRYPT_MODE, encryptionKey(), GCMParameterSpec(128, Base64.decode(wrapper.getString("iv"), Base64.DEFAULT)))
        }
        val data = JSONObject(cipher.doFinal(Base64.decode(wrapper.getString("data"), Base64.DEFAULT)).toString(StandardCharsets.UTF_8))
        val raw = Base64.decode(data.getString("privateKey"), Base64.DEFAULT)
        require(raw.size == 32)
        val privateKey = KeyFactory.getInstance("EC").generatePrivate(ECPrivateKeySpec(BigInteger(1, raw), curveParams()))
        val publicBytes = Base64.decode(data.getString("publicKey"), Base64.DEFAULT)
        require(publicBytes.size == 64 && publicBytes.contentEquals(TravelCardCrypto.publicKeyFromPrivate(raw)))
        return SigningIdentity(privateKey, publicBytes, data.getLong("lastRevision"))
    }
}

internal object TravelCardBuilder {
    fun create(context: Context, options: SharingOptions, profile: UserProfile, data: AppData): File {
        val identity = SharingIdentity.next(context)
        val displayName = options.displayName.trim().ifEmpty { profile.name.trim() }.take(60)
        require(displayName.isNotEmpty())
        val photo = if (options.includePhoto) profile.photoData?.let { prepareProfilePhoto(it, 512) } else null
        val visits = if (options.includeBeen) data.visitRecords.map { visit ->
            TravelCardRecord(visit.countryCode,
                if (options.beenFields.dates) visit.startDate?.toString() else null,
                if (options.beenFields.dates) visit.endDate?.toString() else null,
                if (options.beenFields.length) visit.dayCount?.toInt() else null,
                if (options.beenFields.location) visit.location else null,
                if (options.beenFields.purpose) visit.purpose.name else null)
        } else null
        val plans = if (options.includeWishlist) data.plannedTripRecords.map { plan ->
            TravelCardRecord(plan.countryCode,
                if (options.wishlistFields.dates && plan.durationMode == PlannedDurationMode.dates) plan.startDate?.toString() else null,
                if (options.wishlistFields.dates && plan.durationMode == PlannedDurationMode.dates) plan.endDate?.toString() else null,
                if (options.wishlistFields.length) plan.plannedDayCount?.toInt() else null,
                if (options.wishlistFields.location) plan.location else null,
                if (options.wishlistFields.purpose) plan.purpose.name else null)
        } else null
        val payload = TravelCardPayload(
            TravelCardCrypto.sharerID(identity.publicKey), identity.lastRevision, Instant.now().toString(), displayName,
            photo, visits, plans, options.includePhoto,
            if (options.includeBeen) options.beenFields else null,
            if (options.includeWishlist) options.wishlistFields else null,
        ).validate()
        val folder = File(context.cacheDir, "travel-cards/${UUID.randomUUID()}").apply {
            if (!mkdirs()) throw IOException("Cannot create travel card")
        }
        val safeName = displayName.replace(Regex("[/\\\\?%*:|\"<>\\p{Cntrl}]"), "").trim().ifEmpty { "Travel Card" }
        return File(folder, "$safeName.wcigcard").also {
            writeAtomic(it, TravelCardCrypto.encode(payload, identity.privateKey, identity.publicKey).decodeToString())
        }
    }

    fun shareIntent(context: Context, file: File): Intent {
        val uri = androidx.core.content.FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        return Intent.createChooser(Intent(Intent.ACTION_SEND).apply {
            type = "application/vnd.com.marcocheung.wherecanigo.travelcard"
            putExtra(Intent.EXTRA_STREAM, uri)
            clipData = android.content.ClipData.newRawUri("Travel card", uri)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
    }
}

internal class FriendStore(context: Context) {
    private val file = File(context.filesDir, "friends.json")
    var friends: List<TravelCardFriend> = emptyList()
        private set
    var loadFailed: Boolean = false
        private set

    init { load() }

    fun load() {
        try {
            friends = if (!file.exists()) emptyList() else {
                val json = JSONObject(file.readText())
                require(json.getInt("schemaVersion") == 1)
                json.getJSONArray("friends").objects().map(TravelCardFriend::fromJson)
                    .also { require(it.map(TravelCardFriend::sharerID).distinct().size == it.size) }
            }
            loadFailed = false
        } catch (failure: Exception) {
            Log.e("FriendStore", "Cannot read friend cards", failure)
            loadFailed = true
        }
    }

    fun receipt(card: VerifiedTravelCard, ownID: String?): TravelCardReceipt {
        if (card.sharerID == ownID) return TravelCardReceipt.OwnCard
        val existing = friends.firstOrNull { it.sharerID == card.sharerID }
        if (existing != null) {
            require(existing.publicKey.contentEquals(card.publicKey)) { "Travel card identity collision" }
            return when {
            card.payload.cardRevision > existing.card.cardRevision ->
                TravelCardReceipt.Update(existing)
            card.payload.cardRevision == existing.card.cardRevision ->
                TravelCardReceipt.Unchanged(existing)
            else -> TravelCardReceipt.Older(existing)
            }
        }
        val sameName = friends.filter { it.name.equals(card.payload.displayName, true) ||
            it.card.displayName.equals(card.payload.displayName, true) }
        return TravelCardReceipt.New(sameName)
    }

    fun save(card: VerifiedTravelCard, replacingID: String? = null): TravelCardFriend {
        val old = friends.firstOrNull { it.sharerID == card.sharerID } ?: friends.firstOrNull { it.sharerID == replacingID }
        if (old?.sharerID == card.sharerID) {
            require(old.publicKey.contentEquals(card.publicKey)) { "Travel card identity collision" }
            require(card.payload.cardRevision > old.card.cardRevision) { "Travel card is not newer" }
        }
        val now = Instant.now().truncatedTo(java.time.temporal.ChronoUnit.SECONDS)
        val friend = TravelCardFriend(card.sharerID, card.publicKey, old?.nickname, old?.addedAt ?: now, now, card.payload)
        persist(friends.filterNot { it.sharerID == card.sharerID || it.sharerID == replacingID } + friend)
        return friend
    }

    fun rename(id: String, nickname: String?) {
        persist(friends.map { if (it.sharerID == id) it.copy(nickname = nickname?.trim()?.take(60)?.takeIf(String::isNotEmpty)) else it })
    }

    fun remove(id: String) = persist(friends.filterNot { it.sharerID == id })

    fun replaceAll(newFriends: List<TravelCardFriend>) = persist(newFriends)

    fun merge(incoming: List<TravelCardFriend>): Int {
        val merged = friends.associateBy { it.sharerID }.toMutableMap()
        var changed = 0
        incoming.forEach { friend ->
            val existing = merged[friend.sharerID]
            if (existing == null) { merged[friend.sharerID] = friend; changed++ }
            else if (existing.publicKey.contentEquals(friend.publicKey) && friend.card.cardRevision > existing.card.cardRevision) {
                merged[friend.sharerID] = existing.copy(card = friend.card,
                    lastReceivedAt = maxOf(existing.lastReceivedAt, friend.lastReceivedAt),
                    nickname = existing.nickname ?: friend.nickname)
                changed++
            }
        }
        if (changed > 0) persist(merged.values.toList())
        return changed
    }

    private fun persist(value: List<TravelCardFriend>) {
        require(value.map(TravelCardFriend::sharerID).distinct().size == value.size)
        writeAtomic(file, JSONObject().put("schemaVersion", 1)
            .put("friends", JSONArray(value.map(TravelCardFriend::toJson))).toString())
        friends = value
        loadFailed = false
    }
}

internal fun JSONObject.putNullable(name: String, value: Any?): JSONObject = if (value == null) this else put(name, value)
internal fun JSONObject.optNullable(name: String): String? =
    if (!has(name) || isNull(name)) null else getString(name)
