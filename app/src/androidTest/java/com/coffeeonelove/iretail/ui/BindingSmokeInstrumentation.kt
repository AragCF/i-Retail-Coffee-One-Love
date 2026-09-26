package com.coffeeonelove.iretail.ui

import android.app.Activity
import android.app.Instrumentation
import android.content.Context
import android.content.Intent
import android.content.pm.ActivityInfo
import android.content.pm.ApplicationInfo
import android.os.Build
import android.os.Bundle
import android.view.View
import android.view.ViewGroup
import android.view.WindowManager
import android.widget.EditText
import org.json.JSONObject
import java.io.File
import java.security.KeyStore
import java.util.UUID

/** Runs only in a fresh API23 emulator. Never installed or invoked on a real JL22. */
class BindingSmokeInstrumentation : Instrumentation() {
    private val passed = ArrayList<String>()
    private fun verify(name: String, condition: Boolean) {
        check(condition) { name }
        passed.add(name)
    }
    override fun onCreate(arguments: Bundle?) { super.onCreate(arguments); start() }
    override fun onStart() {
        val output = Bundle()
        try {
            check(Build.VERSION.SDK_INT == 23 && Build.HARDWARE in setOf("goldfish", "ranchu")) { "EMULATOR_API23_ONLY" }
            val app = targetContext
            val file = File(app.noBackupFilesDir, "device_binding_v1.bin")
            check(!file.exists() && !File(file.path + ".bak").exists()) { "FRESH_EMULATOR_ONLY" }
            val storage = DeviceBindingStore.get(app)
            verify("fresh_unbound", storage.read() == null && !storage.isReady())
            verify("financial_gate_closed", !DeviceBindingAccess.financialAllowed())
            verify("backup_disabled", app.applicationInfo.flags and ApplicationInfo.FLAG_ALLOW_BACKUP == 0)
            val monitor = addMonitor(DeviceBindingActivity::class.java.name, null, false)
            runOnMainSync {
                app.startActivity(Intent(app, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            }
            val wizard = monitor.waitForActivityWithTimeout(6000)
            verify("main_redirects_to_binding", wizard is DeviceBindingActivity)
            waitForIdleSync()
            runOnMainSync {
                verify("credential_screen_protected", wizard.window.attributes.flags and WindowManager.LayoutParams.FLAG_SECURE != 0)
                val inputs = ArrayList<EditText>()
                fun visit(view: View) {
                    if (view is EditText) inputs.add(view)
                    if (view is ViewGroup) for (i in 0 until view.childCount) visit(view.getChildAt(i))
                }
                visit(wizard.window.decorView)
                verify("six_runtime_fields_present", inputs.size == 6)
                verify("passwords_not_saved_in_view_state", inputs.all { !it.isSaveEnabled })
                verify("target_and_credentials_not_prefilled", inputs.count { it.text.isNotEmpty() } == 1)
                verify("binding_visibility_survives_main_finish", MainUiVisibility.started)
                wizard.requestedOrientation = ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE
            }
            val landscape = monitor.waitForActivityWithTimeout(6000)
            verify("orientation_recreates_binding_not_catalog", landscape is DeviceBindingActivity)
            waitForIdleSync()
            runOnMainSync { landscape.finish() }
            removeMonitor(monitor)
            waitForIdleSync()
            verify("orientation_did_not_activate", storage.read() == null)

            val record = JSONObject().put("schema",1).put("stage","READY")
                .put("binding_id",UUID.randomUUID().toString()).put("expected_device_id","41")
                .put("expected_channel_id","81").put("catalog_ready",true).put("services_ready",true)
                .put("device_code_encoded","SYNTHETIC_NOT_VALID_FOR_API")
                .put("credentials",BindingCredentials("synthetic-user","synthetic-password","SYNTHETIC","synthetic-secret").json())
                .put("registration",JSONObject("""{"status":true,"result":{"device_id":41,"device_inner_id":2,"channel_id":81,"type_slug":"vending"}}"""))
                .put("channel",JSONObject("""{"status":true,"result":{"id":81,"profile_id":61,"currency":{"id":643,"code":"RUB"}}}"""))
            storage.write(record)
            verify("keystore_encrypts_on_android23", storage.isReady() && file.length() > 32)
            val first = file.readBytes()
            val text = String(first, Charsets.ISO_8859_1)
            verify("credentials_absent_from_ciphertext", !text.contains("synthetic-password") && !text.contains("synthetic-secret"))
            fun freshStore(): DeviceBindingStore = DeviceBindingStore::class.java
                .getDeclaredConstructor(Context::class.java).apply { isAccessible = true }.newInstance(app)
            verify("fresh_store_decrypts_existing_record", freshStore().isReady())
            storage.write(record)
            verify("each_write_has_new_gcm_nonce", !first.contentEquals(file.readBytes()))
            val valid = file.readBytes()
            File(file.path + ".bak").writeBytes(valid)
            file.writeBytes(byteArrayOf(1,2,3))
            verify("atomic_backup_recovery", freshStore().isReady() && file.readBytes().contentEquals(valid))
            val tampered = valid.clone().apply { this[lastIndex] = (this[lastIndex].toInt() xor 1).toByte() }
            file.writeBytes(tampered)
            val damaged = freshStore()
            verify("tamper_is_rejected", runCatching { damaged.read() }.isFailure)
            verify("tamper_preserves_evidence", file.readBytes().contentEquals(tampered))
            verify("tamper_locks_operations", !DeviceBindingAccess.isReady() && !DeviceBindingAccess.financialAllowed())
            file.writeBytes(valid)
            val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
            ks.deleteEntry("iretail.device.binding.aes.v1")
            verify("missing_key_never_auto_rebinds", runCatching { freshStore().read() }.isFailure)
            verify("missing_key_keeps_ciphertext", file.readBytes().contentEquals(valid))
            output.putString("result", "BINDING_ANDROID23_SMOKE_OK")
            output.putInt("checks",passed.size)
            output.putString("passed",passed.joinToString(","))
            output.putString("network","NO_AUTH_REGISTRATION_PAYMENT_OR_BREW_REQUESTS")
            finish(Activity.RESULT_OK, output)
        } catch (e: Throwable) {
            output.putString("result","BINDING_ANDROID23_SMOKE_FAILED")
            output.putInt("checks",passed.size)
            output.putString("failure",e.javaClass.simpleName + ":" + e.message.orEmpty().take(180))
            finish(Activity.RESULT_CANCELED,output)
        }
    }
}
