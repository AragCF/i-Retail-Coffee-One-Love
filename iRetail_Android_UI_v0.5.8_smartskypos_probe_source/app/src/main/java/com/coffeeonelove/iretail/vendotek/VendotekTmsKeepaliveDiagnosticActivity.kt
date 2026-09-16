package com.coffeeonelove.iretail.vendotek

import android.app.Activity
import android.graphics.Color
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors
import kotlin.math.min

/**
 * Non-financial Vendotek TMS keepalive diagnostic.
 *
 * The only management command this activity can send is POS Management Data "A"
 * (Send keepalive / TMS synchronisation) from VTK-MAN-RU 1.0 section 3.2.2.
 * It does NOT implement VRP, FIN, ABR, DIS, SW update, restart, log upload or settlement.
 *
 * This is not strictly read-only: if the terminal can reach TMS, a synchronisation can
 * consume server-side configuration that was already staged for the terminal. For that
 * reason an explicit intent extra is required before any protocol write is allowed.
 */
class VendotekTmsKeepaliveDiagnosticActivity : Activity() {
    private val executor = Executors.newSingleThreadExecutor()
    private lateinit var output: TextView
    private val text = StringBuilder()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        buildUi()
        executor.execute { runProbe() }
    }

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }

    private fun buildUi() {
        val root = LinearLayout(this).apply {
            orientation = LinearLayout.VERTICAL
            setPadding(dp(14), dp(14), dp(14), dp(14))
            setBackgroundColor(Color.WHITE)
        }
        root.addView(TextView(this).apply {
            text = "Vendotek VTK — TMS keepalive probe"
            textSize = 20f
            setTextColor(Color.BLACK)
        })
        root.addView(TextView(this).apply {
            text = "Без оплаты. Один TMS keepalive (A) после явного разрешения. VRP/FIN/ABR/DIS отключены."
            textSize = 13f
            setTextColor(0xFF7A4A00.toInt())
            setPadding(0, dp(5), 0, dp(8))
        })
        output = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.BLACK)
            setTextIsSelectable(true)
        }
        root.addView(
            ScrollView(this).apply { addView(output) },
            LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, 0, 1f)
        )
        setContentView(root)
    }

    private fun runProbe() {
        var input: FileInputStream? = null
        var outputStream: FileOutputStream? = null
        var writes = 0
        var managementWrites = 0
        try {
            val authorised = intent.getBooleanExtra(EXTRA_ALLOW_TMS_KEEPALIVE, false)
            line("TMS_PROBE_BEGIN uid=${android.os.Process.myUid()} authorised=$authorised tty=$TTY_PATH")
            if (!authorised) {
                errorMarker("VTK_TMS_NOT_AUTHORIZED noProtocolWrite=true")
                return
            }

            if (!VtkCodec.selfTest()) {
                errorMarker("VTK_CODEC_SELFTEST_FAILED")
                return
            }
            line("VTK_CODEC_SELFTEST_OK documented=IDL+STATUS+TMS_A")

            val tty = File(TTY_PATH)
            line("TTY_FILE exists=${tty.exists()} canRead=${tty.canRead()} canWrite=${tty.canWrite()}")
            if (!tty.exists() || !tty.canRead() || !tty.canWrite()) {
                errorMarker("VTK_TTY_ACCESS_DENIED")
                return
            }

            val config = configureSerial()
            line("SERIAL_CONFIG rc=${config.first} detail=${safe(config.second)}")
            if (config.first != 0) {
                errorMarker("VTK_SERIAL_CONFIG_ERROR rc=${config.first}")
                return
            }

            input = FileInputStream(tty)
            outputStream = FileOutputStream(tty)
            line("TTY_OPEN_OK uid=${android.os.Process.myUid()}")
            drain(input)

            val rx = RxState()
            var lastTxAt = 0L

            val idl = VtkCodec.buildIdl(localTime())
            line("IDL_TX bytes=${idl.size} hex=${VtkCodec.hex(idl)}")
            outputStream.write(idl)
            outputStream.flush()
            writes++
            lastTxAt = SystemClock.elapsedRealtime()
            val idlResponse = awaitIdl(input, rx, 8_000, requireSystemInfo = false)
            if (idlResponse == null) {
                errorMarker("VTK_TMS_IDL_TIMEOUT")
                return
            }
            line("VTK_IDL_OK operation=${idlResponse.ascii(VtkCodec.TAG_OPERATION_NUMBER) ?: "-"}")

            rateLimit(lastTxAt)
            val statusBeforeRequest = VtkCodec.buildSystemInfo(localTime(), "STATUS")
            line("STATUS_BEFORE_TX bytes=${statusBeforeRequest.size} hex=${VtkCodec.hex(statusBeforeRequest)}")
            outputStream.write(statusBeforeRequest)
            outputStream.flush()
            writes++
            lastTxAt = SystemClock.elapsedRealtime()
            val statusBefore = awaitIdl(input, rx, 8_000, requireSystemInfo = true)
                ?.ascii(VtkCodec.TAG_SYSTEM_INFO) ?: "<timeout-or-missing>"
            line("STATUS_BEFORE value=${safe(statusBefore)}")

            rateLimit(lastTxAt)
            val tms = VtkCodec.buildTmsKeepalive(localTime())
            line("TMS_KEEPALIVE_TX command=A bytes=${tms.size} hex=${VtkCodec.hex(tms)}")
            outputStream.write(tms)
            outputStream.flush()
            writes++
            managementWrites++
            lastTxAt = SystemClock.elapsedRealtime()

            val observation = observeAfterTms(input, rx, OBSERVE_MS)
            line(
                "TMS_OBSERVATION ackA=${observation.ackA} con=${observation.con} dat=${observation.dat} " +
                    "dsc=${observation.dsc} stage921=${observation.stage921} stage922=${observation.stage922} " +
                    "frames=${observation.frames}"
            )

            rateLimit(lastTxAt)
            val statusAfterRequest = VtkCodec.buildSystemInfo(localTime(), "STATUS")
            line("STATUS_AFTER_TX bytes=${statusAfterRequest.size} hex=${VtkCodec.hex(statusAfterRequest)}")
            outputStream.write(statusAfterRequest)
            outputStream.flush()
            writes++
            lastTxAt = SystemClock.elapsedRealtime()
            val statusAfter = awaitIdl(input, rx, 8_000, requireSystemInfo = true)
                ?.ascii(VtkCodec.TAG_SYSTEM_INFO) ?: "<timeout-or-missing>"
            line("STATUS_AFTER value=${safe(statusAfter)}")

            val upperAfter = statusAfter.uppercase(Locale.US)
            val cleanReady = upperAfter.contains("STATE=READY") &&
                !upperAfter.contains("NOT_READY") &&
                !upperAfter.contains("BUSY") &&
                !upperAfter.contains("DISABLED") &&
                !upperAfter.contains("IN_SERVICE")

            if (cleanReady) {
                line("VTK_TMS_RESULT READY_AFTER_TMS")
            } else if (observation.con || observation.stage921) {
                line("VTK_TMS_RESULT INTERNET_OVER_VTK_REQUESTED")
            } else if (observation.ackA) {
                line("VTK_TMS_RESULT KEEPALIVE_ACK_NO_NETWORK_REQUEST")
            } else {
                line("VTK_TMS_RESULT NO_TMS_ACTIVITY_OBSERVED")
            }

            successMarker(
                "VTK_TMS_PROBE_COMPLETE managementWrites=$managementWrites financialCommands=0 " +
                    "preStatus=${safe(statusBefore)} postStatus=${safe(statusAfter)}"
            )
        } catch (e: Exception) {
            errorMarker(
                "VTK_TMS_PROBE_ERROR ${e.javaClass.simpleName}:${safe(e.message)} " +
                    "cause=${e.cause?.javaClass?.simpleName ?: "-"}:${safe(e.cause?.message)}"
            )
        } finally {
            try { outputStream?.close() } catch (_: Exception) {}
            try { input?.close() } catch (_: Exception) {}
            line("TMS_PROBE_END writes=$writes managementWrites=$managementWrites financialCommands=0")
        }
    }

    private data class RxState(var pending: ByteArray = ByteArray(0))

    private data class Observation(
        var ackA: Boolean = false,
        var con: Boolean = false,
        var dat: Boolean = false,
        var dsc: Boolean = false,
        var stage921: Boolean = false,
        var stage922: Boolean = false,
        var frames: Int = 0
    )

    private fun observeAfterTms(input: FileInputStream, state: RxState, timeoutMs: Long): Observation {
        val result = Observation()
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline && !Thread.currentThread().isInterrupted) {
            val frames = readAvailableFrames(input, state)
            if (frames.isEmpty()) {
                Thread.sleep(20)
                continue
            }
            for (frame in frames) {
                result.frames++
                val message = frame.ascii(VtkCodec.TAG_MESSAGE_NAME) ?: "-"
                val management = frame.asciiAll(VtkCodec.TAG_POS_MANAGEMENT_DATA).joinToString("|").ifBlank { "-" }
                val stage = frame.asciiAll(VtkCodec.TAG_STAGE_ID).joinToString("|").ifBlank { "-" }
                val systemInfo = frame.ascii(VtkCodec.TAG_SYSTEM_INFO) ?: "-"
                line(
                    "TMS_RX discriminator=0x${frame.discriminator.toString(16)} crcOk=${frame.crcOk} " +
                        "message=$message management=${safe(management)} stage=${safe(stage)} " +
                        "systemInfo=${safe(systemInfo)} raw=${VtkCodec.hex(frame.raw)}"
                )
                if (frame.discriminator != VtkCodec.POS_TO_VMC || !frame.crcOk) continue
                if (message == "IDL" && management.split('|').any { it == "A" }) result.ackA = true
                if (message == "CON") result.con = true
                if (message == "DAT") result.dat = true
                if (message == "DSC") result.dsc = true
                if (stage.split('|').any { it == "921" }) result.stage921 = true
                if (stage.split('|').any { it == "922" }) result.stage922 = true
            }
        }
        return result
    }

    private fun awaitIdl(
        input: FileInputStream,
        state: RxState,
        timeoutMs: Long,
        requireSystemInfo: Boolean
    ): VtkCodec.Frame? {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline && !Thread.currentThread().isInterrupted) {
            val frames = readAvailableFrames(input, state)
            if (frames.isEmpty()) {
                Thread.sleep(20)
                continue
            }
            for (frame in frames) {
                val message = frame.ascii(VtkCodec.TAG_MESSAGE_NAME)
                val info = frame.ascii(VtkCodec.TAG_SYSTEM_INFO)
                line(
                    "VTK_RX_FRAME discriminator=0x${frame.discriminator.toString(16)} crcOk=${frame.crcOk} " +
                        "message=${message ?: "-"} management=${safe(frame.ascii(VtkCodec.TAG_POS_MANAGEMENT_DATA))} " +
                        "stage=${safe(frame.ascii(VtkCodec.TAG_STAGE_ID))} systemInfo=${safe(info)} raw=${VtkCodec.hex(frame.raw)}"
                )
                if (frame.discriminator != VtkCodec.POS_TO_VMC || !frame.crcOk || message != "IDL") continue
                if (requireSystemInfo && info == null) continue
                if (!requireSystemInfo && info != null) continue
                return frame
            }
        }
        return null
    }

    private fun readAvailableFrames(input: FileInputStream, state: RxState): List<VtkCodec.Frame> {
        val available = input.available()
        if (available <= 0) return emptyList()
        val buffer = ByteArray(min(available, 4096))
        val count = input.read(buffer)
        if (count <= 0) return emptyList()
        val merged = ByteArray(state.pending.size + count)
        System.arraycopy(state.pending, 0, merged, 0, state.pending.size)
        System.arraycopy(buffer, 0, merged, state.pending.size, count)
        val extracted = VtkCodec.extractFrames(merged)
        state.pending = extracted.second
        val result = mutableListOf<VtkCodec.Frame>()
        for (raw in extracted.first) {
            try {
                result += VtkCodec.parseOne(raw)
            } catch (e: Exception) {
                line("VTK_RX_PARSE_ERROR ${e.javaClass.simpleName}:${safe(e.message)} raw=${VtkCodec.hex(raw)}")
            }
        }
        return result
    }

    private fun rateLimit(lastTxAt: Long) {
        if (lastTxAt <= 0L) return
        val due = lastTxAt + MIN_IDL_INTERVAL_MS
        while (SystemClock.elapsedRealtime() < due && !Thread.currentThread().isInterrupted) {
            val left = due - SystemClock.elapsedRealtime()
            if (left > 0) Thread.sleep(min(left, 250L))
        }
    }

    private fun drain(input: FileInputStream) {
        var drained = 0
        val buffer = ByteArray(512)
        val until = SystemClock.elapsedRealtime() + 250
        while (SystemClock.elapsedRealtime() < until) {
            val available = input.available()
            if (available > 0) {
                val count = input.read(buffer, 0, min(available, buffer.size))
                if (count > 0) drained += count
            } else {
                Thread.sleep(10)
            }
        }
        line("RX_DRAINED bytes=$drained")
    }

    private fun localTime(): String =
        SimpleDateFormat("yyyyMMdd'T'HHmmssZ", Locale.US).format(Date())

    private fun configureSerial(): Pair<Int, String> {
        val fullArgs = listOf(
            "stty", "-F", TTY_PATH,
            "115200", "raw", "-echo", "cs8", "-parenb", "-cstopb",
            "-ixon", "-ixoff", "-crtscts", "clocal", "cread"
        )
        val fallbackArgs = listOf(
            "stty", "-F", TTY_PATH,
            "115200", "raw", "-echo", "cs8", "-parenb", "-cstopb", "clocal", "cread"
        )

        val directFull = exec(listOf(BUSYBOX) + fullArgs)
        line("SERIAL_CONFIG_DIRECT_FULL rc=${directFull.first} detail=${safe(directFull.second)}")
        if (directFull.first == 0) return 0 to "direct-full"

        val directFallback = exec(listOf(BUSYBOX) + fallbackArgs)
        line("SERIAL_CONFIG_DIRECT_FALLBACK rc=${directFallback.first} detail=${safe(directFallback.second)}")
        if (directFallback.first == 0) return 0 to "direct-fallback"

        val rootFull = execRoot(listOf(BUSYBOX) + fullArgs)
        line("SERIAL_CONFIG_ROOT_FULL rc=${rootFull.first} detail=${safe(rootFull.second)}")
        if (rootFull.first == 0) return 0 to "root-full"

        val rootFallback = execRoot(listOf(BUSYBOX) + fallbackArgs)
        line("SERIAL_CONFIG_ROOT_FALLBACK rc=${rootFallback.first} detail=${safe(rootFallback.second)}")
        if (rootFallback.first == 0) return 0 to "root-fallback"

        return rootFallback.first to "serial-config-failed"
    }

    private fun execRoot(command: List<String>): Pair<Int, String> {
        val shell = command.joinToString(" ") { shellQuote(it) }
        return exec(listOf(SU, "-c", shell))
    }

    private fun shellQuote(value: String): String {
        if (value.matches(Regex("[A-Za-z0-9_./:=+,-]+"))) return value
        return "'" + value.replace("'", "'\\''") + "'"
    }

    private fun exec(command: List<String>, timeoutMs: Long = 5_000): Pair<Int, String> {
        return try {
            val process = ProcessBuilder(command).redirectErrorStream(true).start()
            val deadline = SystemClock.elapsedRealtime() + timeoutMs
            var rc: Int? = null
            while (SystemClock.elapsedRealtime() < deadline) {
                try {
                    rc = process.exitValue()
                    break
                } catch (_: IllegalThreadStateException) {
                    Thread.sleep(25)
                }
            }
            if (rc == null) {
                try { process.destroy() } catch (_: Exception) {}
                -124 to "timeout command=${command.joinToString(" ")}"
            } else {
                val detail = try {
                    process.inputStream.bufferedReader().use { it.readText() }.trim()
                } catch (e: Exception) {
                    "output-read-error ${e.javaClass.simpleName}:${e.message}"
                }
                rc to detail
            }
        } catch (e: Exception) {
            -126 to "exec-error ${e.javaClass.simpleName}:${e.message}; cause=${e.cause?.javaClass?.simpleName}:${e.cause?.message}"
        }
    }

    private fun successMarker(message: String) {
        Log.i(TAG, message)
        line(message, alreadyLogged = true)
    }

    private fun errorMarker(message: String) {
        Log.e(TAG, message)
        line(message, alreadyLogged = true)
    }

    private fun line(message: String, alreadyLogged: Boolean = false) {
        if (!alreadyLogged) Log.i(TAG, message)
        synchronized(text) {
            if (text.isNotEmpty()) text.append('\n')
            text.append(message)
            if (text.length > 60_000) text.delete(0, text.length - 50_000)
            val snapshot = text.toString()
            runOnUiThread { output.text = snapshot }
        }
    }

    private fun safe(value: String?): String {
        if (value.isNullOrBlank()) return "-"
        return value.replace('\n', ' ').replace('\r', ' ').take(1200)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val TAG = "IretailVendotek"
        const val EXTRA_ALLOW_TMS_KEEPALIVE = "allow_tms_keepalive"
        private const val TTY_PATH = "/dev/ttyUSB0"
        private const val BUSYBOX = "/sbin/busybox"
        private const val SU = "/system/bin/su"
        private const val MIN_IDL_INTERVAL_MS = 10_100L
        private const val OBSERVE_MS = 45_000L
    }
}
