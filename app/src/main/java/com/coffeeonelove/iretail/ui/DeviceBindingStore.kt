package com.coffeeonelove.iretail.ui

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import org.json.JSONObject
import java.io.File
import java.nio.ByteBuffer
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/** One encrypted, atomic record. No fallback to plaintext, asset identity, or a replacement key. */
class DeviceBindingStore private constructor(context: Context) : BindingStorage {
    private val app = context.applicationContext
    private val file = File(app.noBackupFilesDir, "device_binding_v1.bin")
    private val atomic = AtomicFile(file)
    private var loaded = false
    private var cached: String? = null
    private var failed = false

    @Synchronized override fun read(): JSONObject? {
        if (failed) throw BindingFailure("BINDING_STORAGE_LOCKED")
        if (!loaded) {
            try {
                if (file.exists() || File(file.path + ".bak").exists()) {
                    val bytes = atomic.openRead().use { input ->
                        val buffer = java.io.ByteArrayOutputStream()
                        val chunk = ByteArray(8192)
                        while (true) {
                            val n = input.read(chunk)
                            if (n < 0) break
                            if (buffer.size() + n > 2_000_000) throw BindingFailure("BINDING_TOO_LARGE")
                            buffer.write(chunk, 0, n)
                        }
                        buffer.toByteArray()
                    }
                    require(bytes.size > 33 && bytes[0] == 1.toByte()) { "BINDING_FILE_FORMAT" }
                    val iv = bytes.copyOfRange(1, 13)
                    val cipher = Cipher.getInstance("AES/GCM/NoPadding")
                    cipher.init(Cipher.DECRYPT_MODE, key(false), GCMParameterSpec(128, iv))
                    cipher.updateAAD(app.packageName.toByteArray(Charsets.UTF_8))
                    cached = String(cipher.doFinal(bytes.copyOfRange(13, bytes.size)), Charsets.UTF_8)
                    require(JSONObject(cached!!).getInt("schema") == 1) { "BINDING_SCHEMA" }
                }
                loaded = true
                DeviceBindingAccess.publish(cached?.let { JSONObject(it) })
            } catch (_: Exception) {
                failed = true
                DeviceBindingAccess.publish(null)
                throw BindingFailure("BINDING_STORAGE_LOCKED")
            }
        }
        return cached?.let { JSONObject(it) }
    }

    @Synchronized override fun write(record: JSONObject) {
        read()
        require(record.getInt("schema") == 1) { "BINDING_SCHEMA" }
        val text = record.toString()
        require(text.toByteArray(Charsets.UTF_8).size <= 1_000_000) { "BINDING_TOO_LARGE" }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(true))
        cipher.updateAAD(app.packageName.toByteArray(Charsets.UTF_8))
        require(cipher.iv.size == 12) { "BINDING_IV" }
        val encrypted = cipher.doFinal(text.toByteArray(Charsets.UTF_8))
        val bytes = ByteBuffer.allocate(13 + encrypted.size).put(1.toByte()).put(cipher.iv).put(encrypted).array()
        var stream: java.io.FileOutputStream? = null
        try {
            stream = atomic.startWrite()
            stream.write(bytes)
            stream.fd.sync()
            atomic.finishWrite(stream)
            cached = text
            loaded = true
            DeviceBindingAccess.publish(JSONObject(text))
        } catch (_: Exception) {
            if (stream != null) atomic.failWrite(stream)
            throw BindingFailure("BINDING_SAVE_FAILED")
        }
    }

    private fun key(create: Boolean): SecretKey {
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        val existing = ks.getKey(ALIAS, null) as? SecretKey
        if (existing != null) return existing
        if (!create || file.exists() || File(file.path + ".bak").exists()) throw BindingFailure("BINDING_KEY_MISSING")
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
            .setRandomizedEncryptionRequired(true).setKeySize(256).build())
        return gen.generateKey()
    }

    fun isReady(): Boolean = try { BindingRecordPolicy.ready(read()) } catch (_: Exception) { false }
    fun configuredRecord(): JSONObject? = read()?.takeIf { BindingRecordPolicy.configured(it) }
    fun stage(): String = try { read()?.optString("stage") ?: "UNBOUND" } catch (_: Exception) { "STORAGE_LOCKED" }

    companion object {
        private const val ALIAS = "iretail.device.binding.aes.v1"
        @Volatile private var instance: DeviceBindingStore? = null
        fun get(context: Context): DeviceBindingStore = instance ?: synchronized(this) {
            instance ?: DeviceBindingStore(context).also { instance = it }
        }
        fun hasUnresolvedLegacyOperation(context: Context): Boolean {
            val prefs = context.getSharedPreferences("iretail_jl22_kozen_payment_v1", Context.MODE_PRIVATE)
            if (!prefs.getString("unresolved_request_id", "").isNullOrBlank() ||
                !prefs.getString("sbp_probe_unresolved_request_id", "").isNullOrBlank()) return true
            val session = context.getSharedPreferences("iretail_sbp_session_v1", Context.MODE_PRIVATE)
            return session.getBoolean("real_payment_sent", false) && !session.getString("session_id", "").isNullOrBlank()
        }
    }
}
