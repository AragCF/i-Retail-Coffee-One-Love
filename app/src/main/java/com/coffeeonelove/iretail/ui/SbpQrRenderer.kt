package com.coffeeonelove.iretail.ui

import android.graphics.Bitmap
import android.graphics.Color
import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.qrcode.QRCodeWriter

/** Pure renderer: it never creates or confirms a payment, it only renders supplied payload. */
object SbpQrRenderer {
    fun render(payload: String, sizePx: Int): Bitmap {
        require(payload.isNotBlank()) { "SBP QR payload is empty" }
        val size = sizePx.coerceIn(128, 1600)
        val hints = mapOf<EncodeHintType, Any>(
            EncodeHintType.CHARACTER_SET to "UTF-8",
            EncodeHintType.MARGIN to 1
        )
        val matrix = QRCodeWriter().encode(payload, BarcodeFormat.QR_CODE, size, size, hints)
        val pixels = IntArray(size * size)
        var offset = 0
        for (y in 0 until size) {
            for (x in 0 until size) {
                pixels[offset++] = if (matrix[x, y]) Color.BLACK else Color.WHITE
            }
        }
        return Bitmap.createBitmap(pixels, size, size, Bitmap.Config.ARGB_8888)
    }
}
