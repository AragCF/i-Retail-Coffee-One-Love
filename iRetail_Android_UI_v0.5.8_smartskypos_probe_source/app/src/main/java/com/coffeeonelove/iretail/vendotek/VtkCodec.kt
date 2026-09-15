package com.coffeeonelove.iretail.vendotek

import java.io.ByteArrayOutputStream
import java.nio.charset.Charset

/**
 * Minimal VTK serial codec used by Vendotek diagnostics.
 *
 * Source of truth: VTK-MAN-RU 1.0 (2026-01-19), sections 2.1-2.3 and 3.2.3.
 * Serial frame:
 *   1F | length BE (2) | discriminator BE (2) | BER-TLV application | CRC16-CCITT BE (2)
 * length counts discriminator + application and excludes CRC.
 * CRC covers every byte from 0x1F through the application payload, init 0xFFFF.
 */
object VtkCodec {
    const val START = 0x1F
    const val VMC_TO_POS = 0x96FB
    const val POS_TO_VMC = 0x97FB

    const val TAG_MESSAGE_NAME = 0x01
    const val TAG_OPERATION_NUMBER = 0x03
    const val TAG_KEEPALIVE_SECONDS = 0x05
    const val TAG_LOCAL_TIME = 0x11
    const val TAG_SYSTEM_INFO = 0x12

    private val ASCII: Charset = Charsets.US_ASCII

    data class Frame(
        val discriminator: Int,
        val tlv: Map<Int, List<ByteArray>>,
        val raw: ByteArray,
        val crcOk: Boolean
    ) {
        fun ascii(tag: Int): String? = tlv[tag]?.firstOrNull()?.toString(ASCII)
    }

    fun buildIdl(localTime: String): ByteArray {
        require(localTime.length <= 20) { "VTK local time is longer than 20 bytes" }
        val app = ByteArrayOutputStream()
        writeTlv(app, TAG_MESSAGE_NAME, "IDL".toByteArray(ASCII))
        writeTlv(app, TAG_LOCAL_TIME, localTime.toByteArray(ASCII))
        return buildSerialFrame(VMC_TO_POS, app.toByteArray())
    }

    /**
     * System Information request from VTK-MAN-RU 1.0 section 3.2.3.
     * The request itself is an IDL message with LocalTime (11h) and SystemInformation (12h).
     */
    fun buildSystemInfo(localTime: String, query: String): ByteArray {
        require(localTime.length <= 20) { "VTK local time is longer than 20 bytes" }
        require(query.isNotBlank()) { "VTK SystemInfo query is empty" }
        val app = ByteArrayOutputStream()
        writeTlv(app, TAG_MESSAGE_NAME, "IDL".toByteArray(ASCII))
        writeTlv(app, TAG_LOCAL_TIME, localTime.toByteArray(ASCII))
        writeTlv(app, TAG_SYSTEM_INFO, query.toByteArray(ASCII))
        return buildSerialFrame(VMC_TO_POS, app.toByteArray())
    }

    fun buildSerialFrame(discriminator: Int, application: ByteArray): ByteArray {
        require(application.size <= 65533) { "VTK application payload is too large" }
        val length = 2 + application.size
        val preCrc = ByteArrayOutputStream()
        preCrc.write(START)
        preCrc.write((length ushr 8) and 0xFF)
        preCrc.write(length and 0xFF)
        preCrc.write((discriminator ushr 8) and 0xFF)
        preCrc.write(discriminator and 0xFF)
        preCrc.write(application)
        val raw = preCrc.toByteArray()
        val crc = crc16Ccitt(raw)
        return raw + byteArrayOf(((crc ushr 8) and 0xFF).toByte(), (crc and 0xFF).toByte())
    }

    fun parseOne(raw: ByteArray): Frame {
        require(raw.size >= 7) { "VTK frame too short" }
        require((raw[0].toInt() and 0xFF) == START) { "VTK start byte is not 0x1F" }
        val length = ((raw[1].toInt() and 0xFF) shl 8) or (raw[2].toInt() and 0xFF)
        val total = length + 5
        require(raw.size == total) { "VTK frame length mismatch expected=$total actual=${raw.size}" }
        require(length >= 2) { "VTK discriminator is missing" }

        val discriminator = ((raw[3].toInt() and 0xFF) shl 8) or (raw[4].toInt() and 0xFF)
        val expectedCrc = ((raw[raw.size - 2].toInt() and 0xFF) shl 8) or (raw[raw.size - 1].toInt() and 0xFF)
        val calculatedCrc = crc16Ccitt(raw.copyOfRange(0, raw.size - 2))
        val tlvEnd = 3 + length
        val tlv = parseTlv(raw, 5, tlvEnd)
        return Frame(discriminator, tlv, raw, expectedCrc == calculatedCrc)
    }

    /** Extract complete serial frames from an arbitrary receive buffer. */
    fun extractFrames(buffer: ByteArray): Pair<List<ByteArray>, ByteArray> {
        val frames = mutableListOf<ByteArray>()
        var offset = 0
        while (offset < buffer.size) {
            while (offset < buffer.size && (buffer[offset].toInt() and 0xFF) != START) offset++
            if (offset >= buffer.size) return frames to ByteArray(0)
            if (buffer.size - offset < 3) return frames to buffer.copyOfRange(offset, buffer.size)
            val length = ((buffer[offset + 1].toInt() and 0xFF) shl 8) or (buffer[offset + 2].toInt() and 0xFF)
            val total = length + 5
            if (length < 2 || total > 65540) {
                offset++
                continue
            }
            if (buffer.size - offset < total) return frames to buffer.copyOfRange(offset, buffer.size)
            frames += buffer.copyOfRange(offset, offset + total)
            offset += total
        }
        return frames to ByteArray(0)
    }

    fun crc16Ccitt(data: ByteArray): Int {
        var crc = 0xFFFF
        for (byte in data) {
            crc = crc xor ((byte.toInt() and 0xFF) shl 8)
            repeat(8) {
                crc = if ((crc and 0x8000) != 0) {
                    ((crc shl 1) xor 0x1021) and 0xFFFF
                } else {
                    (crc shl 1) and 0xFFFF
                }
            }
        }
        return crc
    }

    /** Known frames from VTK-MAN-RU 1.0 pages 8 and 38. */
    fun selfTest(): Boolean {
        val expectedIdl = hexToBytes("1f001d96fb010349444c11143230323630313237543038343035332b30333030977e")
        val actualIdl = buildIdl("20260127T084053+0300")
        if (!expectedIdl.contentEquals(actualIdl)) return false

        val expectedStatus = hexToBytes("1f002596fb010349444c11143230323630313232543132333930302b3033303012065354415455532349")
        val actualStatus = buildSystemInfo("20260122T123900+0300", "STATUS")
        return expectedStatus.contentEquals(actualStatus)
    }

    fun hex(bytes: ByteArray): String = bytes.joinToString("") { "%02x".format(it.toInt() and 0xFF) }

    private fun writeTlv(out: ByteArrayOutputStream, tag: Int, value: ByteArray) {
        require(tag in 0..0xFF) { "Only one-byte VTK tags are used by this probe" }
        out.write(tag)
        writeBerLength(out, value.size)
        out.write(value)
    }

    private fun writeBerLength(out: ByteArrayOutputStream, length: Int) {
        when {
            length < 0x80 -> out.write(length)
            length <= 0xFF -> {
                out.write(0x81)
                out.write(length)
            }
            length <= 0xFFFF -> {
                out.write(0x82)
                out.write((length ushr 8) and 0xFF)
                out.write(length and 0xFF)
            }
            else -> throw IllegalArgumentException("BER length too large: $length")
        }
    }

    private fun parseTlv(data: ByteArray, start: Int, endExclusive: Int): Map<Int, List<ByteArray>> {
        val result = linkedMapOf<Int, MutableList<ByteArray>>()
        var p = start
        while (p < endExclusive) {
            val tag = data[p++].toInt() and 0xFF
            require(p < endExclusive) { "TLV length missing for tag=$tag" }
            val first = data[p++].toInt() and 0xFF
            val length = if ((first and 0x80) == 0) {
                first
            } else {
                val count = first and 0x7F
                require(count in 1..2) { "Unsupported BER length bytes=$count" }
                require(p + count <= endExclusive) { "Truncated BER length" }
                var value = 0
                repeat(count) { value = (value shl 8) or (data[p++].toInt() and 0xFF) }
                value
            }
            require(p + length <= endExclusive) { "Truncated TLV value tag=$tag length=$length" }
            result.getOrPut(tag) { mutableListOf() }.add(data.copyOfRange(p, p + length))
            p += length
        }
        return result
    }

    private fun hexToBytes(hex: String): ByteArray {
        require(hex.length % 2 == 0)
        return ByteArray(hex.length / 2) { index ->
            hex.substring(index * 2, index * 2 + 2).toInt(16).toByte()
        }
    }
}
