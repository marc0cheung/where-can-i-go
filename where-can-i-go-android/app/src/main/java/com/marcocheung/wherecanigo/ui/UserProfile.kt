package com.marcocheung.wherecanigo.ui

import android.util.Base64
import org.json.JSONObject

data class ProfilePhotoCrop(val zoom: Float = 1f, val offsetX: Float = 0f, val offsetY: Float = 0f) {
    fun toJson() = JSONObject().put("zoom", zoom).put("offsetX", offsetX).put("offsetY", offsetY)
}

data class UserProfile(val name: String = "", val photoData: ByteArray? = null,
    val photoSourceData: ByteArray? = null, val photoCrop: ProfilePhotoCrop? = null) {
    fun toJson() = JSONObject().put("name", name.trim())
        .putOpt("photoData", photoData?.let { Base64.encodeToString(it, Base64.NO_WRAP) })
        .putOpt("photoSourceData", photoSourceData?.let { Base64.encodeToString(it, Base64.NO_WRAP) })
        .putOpt("photoCrop", photoCrop?.toJson())
    companion object {
        fun fromJson(json: JSONObject): UserProfile {
            val crop = json.optJSONObject("photoCrop")
            return UserProfile(json.optString("name", ""), json.nullableString("photoData")?.let { Base64.decode(it, Base64.DEFAULT) },
                json.nullableString("photoSourceData")?.let { Base64.decode(it, Base64.DEFAULT) },
                crop?.let { ProfilePhotoCrop(it.getDouble("zoom").toFloat(), it.getDouble("offsetX").toFloat(), it.getDouble("offsetY").toFloat()) })
        }
    }
}

enum class SearchEngine(val displayName: String, val url: String) {
    google("Google", "https://www.google.com/search"), bing("Bing", "https://www.bing.com/search"),
    duckDuckGo("DuckDuckGo", "https://duckduckgo.com/");
}
