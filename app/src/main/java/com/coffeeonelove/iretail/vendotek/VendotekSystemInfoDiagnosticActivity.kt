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
 * Read-only Vendotek VTK System Information probe.
 *
 * Allowed protocol writes:
 *   1) IDL
 *   2) IDL + SystemInfo STATUS
 *   3) IDL + SystemInfo POS_PARAMS
 *   4) IDL + SystemInfo BANK_PARAMS
 *   5) IDL + SystemInfo NET_PARAMS
 *
 * Messages are rate-limited to >= 10 seconds between IDL transmissions per VTK-MAN-RU 1.0.
 * VRP/FIN/ABR/DIS and every financial command are absent from this diagnostic activity.
 */
class VendotekSystemInfoDiagnosticActivity : Activity() {
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
            text = "Vendotek VTK — SystemInfo"
            textSize = 20f
            setTextColor(Color.BLACK)
        })
        root.addView(TextView(this).apply {
            text = "Только чтение: IDL, STATUS, POS_PARAMS, BANK_PARAMS, NET_PARAMS. Оплаты нет."
            textSize = 13f
            setTextColor(0xFF256029.toInt())
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
        try {
            line("SYSINFO_BEGIN uid=${android.os.Process.myUid()} tty=$TTY_PATH")
            if (!VtkCodec.selfTest()) {
                errorMarker("VTK_CODEC_SELFTEST_FAILED")
                return
            }
            line("VTK_CODEC_SELFTEST_OK documented=IDL+STATUS")

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
                errorMarker("VTK_SYSINFO_IDL_TIMEOUT")
                return
            }
            line(
                "VTK_IDL_OK operation=${idlResponse.ascii(VtkCodec.TAG_OPERATION_NUMBER) ?: "-"} " +
                    "keepalive=${idlResponse.ascii(VtkCodec.TAG_KEEPALIVE_SECONDS) ?: "-"}"
            )

            val results = linkedMapOf<String, String>()
            for (query in QUERIES) {
                rateLimit(lastTxAt)
                val request = VtkCodec.buildSystemInfo(localTime(), query)
                line("SYSINFO_TX query=$query bytes=${request.size} hex=${VtkCodec.hex(request)}")
                outputStream.write(request)
                outputStream.flush()
                writes++
                lastTxAt = SystemClock.elapsedRealtime()

                val response = awaitIdl(input, rx, 8_000, requireSystemInfo = true)
                if (response == null) {
                    results[query] = "<timeout>"
                    line("SYSINFO_TIMEOUT query=$query")
                    continue
                }
                val info = response.ascii(VtkCodec.TAG_SYSTEM_INFO) ?: "<missing>"
                results[query] = info
                line(
                    "SYSINFO_RX query=$query operation=${response.ascii(VtkCodec.TAG_OPERATION_NUMBER) ?: "-"} " +
                        "keepalive=${response.ascii(VtkCodec.TAG_KEEPALIVE_SECONDS) ?: "-"} info=${safe(info)}"
                )
            }

            val status = results["STATUS"] ?: "<missing>"
            val pos = results["POS_PARAMS"] ?: "<missing>"
            val bank = results["BANK_PARAMS"] ?: "<missing>"
            val net = results["NET_PARAMS"] ?: "<missing>"
            line("VTK_STATUS value=${safe(status)}")
            line("VTK_POS_PARAMS value=${safe(pos)}")
            line("VTK_BANK_PARAMS value=${safe(bank)}")
            line("VTK_NET_PARAMS value=${safe(net)}")

            if (status.contains("STATE=READY")) {
                line("VTK_PAYMENT_ROUTE_READY state=$status")
            } else {
                line("VTK_PAYMENT_ROUTE_NOT_READY state=$status")
            }
            successMarker("VTK_SYSTEM_INFO_COMPLETE writes=$writes")
        } catch (e: Exception) {
            errorMarker(
                "VTK_SYSTEM_INFO_ERROR ${e.javaClass.simpleName}:${safe(e.message)} cause=${e.cause?.javaClass?.simpleName ?: "-"}:${safe(e.cause?.message)}"
            )
        } finally {
            try { outputStream?.close() } catch (_: Exception) {}
            try { input?.close() } catch (_: Exception) {}
            line("SYSINFO_END writes=$writes financialCommands=0")
        }
    }

    private data class RxState(var pending: ByteArray = ByteArray(0))

    private fun awaitIdl(
        input: FileInputStream,
        state: RxState,
        timeoutMs: Long,
        requireSystemInfo: Boolean
    ): VtkCodec.Frame? {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        val readBuffer = ByteArray(1024)
        while (SystemClock.elapsedRealtime() < deadline && !Thread.currentThread().isInterrupted) {
            val available = input.available()
            if (available <= 0) {
                Thread.sleep(20)
                continue
            }
            val count = input.read(readBuffer, 0, min(available, readBuffer.size))
            if (count <= 0) continue
            val merged = ByteArray(state.pending.size + count)
            System.arraycopy(state.pending, 0, merged, 0, state.pending.size)
            System.arraycopy(readBuffer, 0, merged, state.pending.size, count)
            val extracted = VtkCodec.extractFrames(merged)
            state.pending = extracted.second
            for (raw in extracted.first) {
                val frame = try {
                    VtkCodec.parseOne(raw)
                } catch (e: Exception) {
                    line("VTK_RX_PARSE_ERROR ${e.javaClass.simpleName}:${safe(e.message)} raw=${VtkCodec.hex(raw)}")
                    continue
                }
                val message = frame.ascii(VtkCodec.TAG_MESSAGE_NAME)
                val info = frame.ascii(VtkCodec.TAG_SYSTEM_INFO)
                line(
                    "VTK_RX_FRAME discriminator=0x${frame.discriminator.toString(16)} crcOk=${frame.crcOk} " +
                        "message=${message ?: "-"} systemInfo=${safe(info)} raw=${VtkCodec.hex(raw)}"
                )
                if (frame.discriminator != VtkCodec.POS_TO_VMC || !frame.crcOk || message != "IDL") continue
                if (requireSystemInfo && info == null) continue
                if (!requireSystemInfo && info != null) {
                    // A queued SystemInfo frame cannot satisfy the initial plain IDL handshake.
                    continue
                }
                return frame
            }
        }
        return null
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
            if (text.length > 45_000) text.delete(0, text.length - 38_000)
            val snapshot = text.toString()
            runOnUiThread { output.text = snapshot }
        }
    }

    private fun safe(value: String?): String {
        if (value.isNullOrBlank()) return "-"
        return value.replace('\n', ' ').replace('\r', ' ').take(1000)
    }

    private fun dp(value: Int): Int = (value * resources.displayMetrics.density).toInt()

    companion object {
        const val TAG = "IretailVendotek"
        private const val TTY_PATH = "/dev/ttyUSB0"
        private const val BUSYBOX = "/sbin/busybox"
        private const val SU = "/system/bin/su"
        private const val MIN_IDL_INTERVAL_MS = 10_100L
        private val QUERIES = listOf("STATUS", "POS_PARAMS", "BANK_PARAMS", "NET_PARAMS")
    }
}
