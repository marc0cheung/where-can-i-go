package com.marcocheung.wherecanigo.ui

import org.json.JSONObject
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

internal fun writeAtomic(file: File, text: String) {
    val temp = File(file.parentFile, file.name + ".tmp")
    try {
        temp.outputStream().use { it.write(text.toByteArray(Charsets.UTF_8)); it.fd.sync() }
        Files.move(temp.toPath(), file.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
    } finally {
        if (temp.exists() && !temp.delete()) android.util.Log.e("LocalStore", "Cannot remove incomplete temporary file")
    }
}

/** A durable rollback journal keeps app data and profile consistent after interrupted imports. */
internal object LocalStore {
    private val files = listOf("app_data.json", "user_profile.json")
    fun recover(root: File) {
        val journal = File(root, "data_transaction.json")
        if (!journal.exists()) return
        val originals = JSONObject(journal.readText())
        files.forEach { name ->
            val target = File(root, name)
            if (originals.isNull(name)) {
                if (target.exists() && !target.delete()) throw java.io.IOException("Cannot restore absent file")
            } else writeAtomic(target, originals.getString(name))
        }
        if (!journal.delete()) throw java.io.IOException("Cannot clear transaction journal")
    }

    fun commit(root: File, app: JSONObject, profile: JSONObject) {
        recover(root)
        val original = JSONObject()
        files.forEach { name -> original.put(name, File(root, name).takeIf(File::exists)?.readText() ?: JSONObject.NULL) }
        val journal = File(root, "data_transaction.json")
        writeAtomic(journal, original.toString())
        try {
            writeAtomic(File(root, files[0]), app.toString(2))
            writeAtomic(File(root, files[1]), profile.toString())
            if (!journal.delete()) throw java.io.IOException("Cannot finalize data transaction")
        } catch (failure: Exception) {
            try { recover(root) } catch (rollback: Exception) { failure.addSuppressed(rollback) }
            throw failure
        }
    }
}
