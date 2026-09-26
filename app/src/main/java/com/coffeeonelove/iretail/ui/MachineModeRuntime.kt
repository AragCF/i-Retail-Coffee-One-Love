package com.coffeeonelove.iretail.ui

import android.app.Activity
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager
import android.util.Log

/** Runtime mode for the JL22 coffee machine installation. */
data class MachineModeConfig(
    val mode: String,
    val realPosEnabled: Boolean
) {
    val standalone: Boolean get() = mode == MachineModeStore.MODE_STANDALONE
}

object MachineModeStore {
    const val MODE_STANDALONE = "standalone"
    const val MODE_KIOSK = "kiosk"

    private const val PREFS = "iretail_machine_mode_v1"
    private const val KEY_MODE = "mode"
    private const val KEY_REAL_POS = "real_pos_enabled"

    fun resolve(context: Context, intent: Intent?): MachineModeConfig {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val persistedMode = normalizeMode(prefs.getString(KEY_MODE, MODE_KIOSK))
        val persistedPos = prefs.getBoolean(KEY_REAL_POS, false)

        val requestedMode = intent?.getStringExtra("machine_mode")?.let(::normalizeMode)
        val requestedPos = if (intent?.hasExtra("real_pos_enabled") == true) {
            intent.getBooleanExtra("real_pos_enabled", false)
        } else null
        val persist = intent?.getBooleanExtra("persist_machine_mode", false) == true

        val mode = requestedMode ?: persistedMode
        val pos = requestedPos ?: persistedPos

        if (persist) {
            prefs.edit()
                .putString(KEY_MODE, mode)
                .putBoolean(KEY_REAL_POS, pos)
                .apply()
            Log.i("IretailMachineMode", "CONFIG_PERSISTED mode=$mode realPos=$pos")
        }

        return MachineModeConfig(mode, pos)
    }

    fun load(context: Context): MachineModeConfig {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return MachineModeConfig(
            normalizeMode(prefs.getString(KEY_MODE, MODE_KIOSK)),
            prefs.getBoolean(KEY_REAL_POS, false)
        )
    }

    fun statusText(context: Context): String {
        val cfg = load(context)
        return "mode=${cfg.mode} realPos=${cfg.realPosEnabled}"
    }

    private fun normalizeMode(value: String?): String {
        return if (value?.lowercase() == MODE_STANDALONE) MODE_STANDALONE else MODE_KIOSK
    }
}

/** Process-local visibility signal used by the standalone foreground keeper. */
object MainUiVisibility {
    @Volatile private var customerStarted: Boolean = false
    @Volatile var bindingStarted: Boolean = false
    var started: Boolean
        get() = customerStarted || bindingStarted
        set(value) { customerStarted = value }
}

/** Starts the i-Retail UI after boot only for standalone coffee-machine mode. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        if (intent?.action != Intent.ACTION_BOOT_COMPLETED) return
        val config = MachineModeStore.load(context)
        Log.i("IretailMachineMode", "BOOT_COMPLETED mode=${config.mode} realPos=${config.realPosEnabled}")
        if (!config.standalone) return

        val launch = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            putExtra("machine_mode", MachineModeStore.MODE_STANDALONE)
            putExtra("real_pos_enabled", config.realPosEnabled)
            putExtra("restored_from_boot", true)
        }
        context.startActivity(launch)
        ForegroundKeeperService.ensureRunning(context)
    }
}

/**
 * Dedicated-device foreground keeper for standalone mode.
 *
 * It does NOT stop or kill the Jetinno application. The stock coffee-machine application
 * remains running in the background; when its screensaver/activity steals the foreground,
 * MainActivity becomes stopped and this service brings i-Retail back to the front.
 * A transient system dialog only pauses MainActivity without stopping it, so USB permission
 * dialogs are not fought by this keeper.
 */
class ForegroundKeeperService : Service() {
    companion object {
        private const val TAG = "IretailForegroundKeeper"
        private const val PERIOD_MS = 750L

        fun ensureRunning(context: Context) {
            val cfg = MachineModeStore.load(context)
            if (!cfg.standalone) {
                context.stopService(Intent(context, ForegroundKeeperService::class.java))
                return
            }
            context.startService(Intent(context, ForegroundKeeperService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, ForegroundKeeperService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val tick = object : Runnable {
        override fun run() {
            val cfg = MachineModeStore.load(this@ForegroundKeeperService)
            if (!cfg.standalone) {
                Log.i(TAG, "STOP_NON_STANDALONE mode=${cfg.mode}")
                stopSelf()
                return
            }

            val power = getSystemService(Context.POWER_SERVICE) as PowerManager
            if (power.isInteractive && !MainUiVisibility.started) {
                val launch = Intent(this@ForegroundKeeperService, MainActivity::class.java).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or Intent.FLAG_ACTIVITY_SINGLE_TOP)
                    putExtra("foreground_keeper", true)
                }
                try {
                    startActivity(launch)
                    Log.i(TAG, "BRING_MAIN_UI_TO_FRONT")
                } catch (e: Exception) {
                    Log.e(TAG, "BRING_MAIN_UI_ERROR ${e.javaClass.simpleName}: ${e.message}")
                }
            }
            handler.postDelayed(this, PERIOD_MS)
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "SERVICE_CREATE ${MachineModeStore.statusText(this)}")
        handler.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return if (MachineModeStore.load(this).standalone) START_STICKY else START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        Log.i(TAG, "SERVICE_DESTROY")
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null
}

/** Helper used by MainActivity to apply the current runtime mode without duplicating policy. */
fun Activity.applyMachineModeRuntime(config: MachineModeConfig) {
    if (config.standalone) ForegroundKeeperService.ensureRunning(this)
    else ForegroundKeeperService.stop(this)
}
