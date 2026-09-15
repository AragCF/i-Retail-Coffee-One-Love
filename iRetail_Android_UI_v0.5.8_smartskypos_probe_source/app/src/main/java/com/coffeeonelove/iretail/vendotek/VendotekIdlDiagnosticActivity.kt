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
 * Non-financial Vendotek serial smoke-test.
 *
 * This activity performs at most one protocol write: VTK IDL.
 * It never sends VRP, FIN, ABR, DIS or any financial command.
 *
 * JL22 exposes /dev/ttyUSB0 through the kernel ftdi_sio driver. The device node
 * is writable by the application, but the factory BusyBox binary may not be
 * directly executable by the app uid. For this diagnostic stage only, serial
 * configuration is attempted directly first and then through factory su.
 * No IDL byte is written unless 115200 8N1 configuration succeeds.
 */
class VendotekIdlDiagnosticActivity : Activity() {
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
            this.text = "Vendotek VTK — IDL smoke-test"
            textSize = 20f
            setTextColor(Color.BLACK)
        })
        root.addView(TextView(this).apply {
            this.text = "Без оплаты: максимум один IDL. VRP/FIN/ABR/DIS отключены."
            textSize = 13f
            setTextColor(0xFF256029.toInt())
            setPadding(0, dp(5), 0, dp(8))
        })
        output = TextView(this).apply {
            textSize = 12f
            setTextColor(Color.BLACK)
            setTextIsSelectable(true)
        }
        val scroll = ScrollView(this).apply { addView(output) }
        root.addView(
            scroll,
            LinearLayout.LayoutParams(
                LinearLayout.LayoutParams.MATCH_PARENT,
                0,
                1f
            )
        )
        setContentView(root)
    }

    private fun runProbe() {
        var input: FileInputStream? = null
        var outputStream: FileOutputStream? = null
        var writeAttempted = false
        try {
            line("PROBE_BEGIN uid=${android.os.Process.myUid()} tty=$TTY_PATH")

            if (!VtkCodec.selfTest()) {
                errorMarker("VTK_CODEC_SELFTEST_FAILED")
                return
            }
            line("VTK_CODEC_SELFTEST_OK documentedFrame=page8 crc=977e")

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

            var drained = 0
            val drainBuffer = ByteArray(512)
            val drainUntil = SystemClock.elapsedRealtime() + 250
            while (SystemClock.elapsedRealtime() < drainUntil) {
                val available = input.available()
                if (available > 0) {
                    val count = input.read(drainBuffer, 0, min(available, drainBuffer.size))
                    if (count > 0) drained += count
                } else {
                    Thread.sleep(10)
                }
            }
            line("RX_DRAINED bytes=$drained")

            val localTime = SimpleDateFormat("yyyyMMdd'T'HHmmssZ", Locale.US).format(Date())
            val request = VtkCodec.buildIdl(localTime)
            line("IDL_TX localTime=$localTime bytes=${request.size} hex=${VtkCodec.hex(request)}")
            writeAttempted = true
            outputStream.write(request)
            outputStream.flush()
            Log.i(TAG, "VTK_IDL_TX_ONLY")

            val deadline = SystemClock.elapsedRealtime() + 12_000
            var pending = ByteArray(0)
            val readBuffer = ByteArray(1024)
            while (SystemClock.elapsedRealtime() < deadline && !Thread.currentThread().isInterrupted) {
                val available = input.available()
                if (available <= 0) {
                    Thread.sleep(20)
                    continue
                }
                val count = input.read(readBuffer, 0, min(available, readBuffer.size))
                if (count <= 0) continue
                val merged = ByteArray(pending.size + count)
                System.arraycopy(pending, 0, merged, 0, pending.size)
                System.arraycopy(readBuffer, 0, merged, pending.size, count)
                val extracted = VtkCodec.extractFrames(merged)
                pending = extracted.second
                for (raw in extracted.first) {
                    line("IDL_RX_FRAME bytes=${raw.size} hex=${VtkCodec.hex(raw)}")
                    val frame = try {
                        VtkCodec.parseOne(raw)
                    } catch (e: Exception) {
                        line("VTK_RX_PARSE_ERROR ${e.javaClass.simpleName}:${safe(e.message)}")
                        continue
                    }
                    val message = frame.ascii(VtkCodec.TAG_MESSAGE_NAME)
                    val operation = frame.ascii(VtkCodec.TAG_OPERATION_NUMBER) ?: "-"
                    val keepalive = frame.ascii(VtkCodec.TAG_KEEPALIVE_SECONDS) ?: "-"
                    line("VTK_RX discriminator=0x${frame.discriminator.toString(16)} crcOk=${frame.crcOk} message=${message ?: "-"} operation=$operation keepalive=$keepalive")
                    if (frame.discriminator == VtkCodec.POS_TO_VMC && frame.crcOk && message == "IDL") {
                        successMarker("VTK_IDL_OK operation=$operation keepalive=$keepalive raw=${VtkCodec.hex(raw)}")
                        return
                    }
                }
            }
            errorMarker("VTK_IDL_TIMEOUT pending=${VtkCodec.hex(pending)}")
        } catch (e: Exception) {
            errorMarker(
                "VTK_IDL_ERROR ${e.javaClass.simpleName}:${safe(e.message)} cause=${e.cause?.javaClass?.simpleName ?: "-"}:${safe(e.cause?.message)}"
            )
        } finally {
            try { outputStream?.close() } catch (_: Exception) {}
            try { input?.close() } catch (_: Exception) {}
            line("PROBE_END onlyCommand=IDL writeAttempted=$writeAttempted")
        }
    }

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

        return rootFallback.first to buildString {
            append("directFull=").append(directFull.first)
            append(" directFallback=").append(directFallback.first)
            append(" rootFull=").append(rootFull.first)
            append(" rootFallback=").append(rootFallback.first)
            append(" last=").append(safe(rootFallback.second))
        }
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
            if (text.length > 30_000) text.delete(0, text.length - 25_000)
            val snapshot = text.toString()
            runOnUiThread { output.text = snapshot }
        }
    }

    private fun safe(value: String?): String {
        if (value.isNullOrBlank()) return "-"
        return value.replace('\n', ' ').replace('\r', ' ').take(700)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val TAG = "IretailVendotek"
        private const val TTY_PATH = "/dev/ttyUSB0"
        private const val BUSYBOX = "/sbin/busybox"
        private const val SU = "/system/bin/su"
    }
}
