package com.coffeeonelove.iretail.ui

import java.math.BigDecimal
import java.math.RoundingMode

/**
 * Денежные значения внутри приложения хранятся в минимальных единицах валюты.
 * Для RUB это копейки. Никаких Double/Float и молчаливого округления.
 */
object Money {
    private const val MINOR_FACTOR = 100L

    fun parseMinor(value: String): Long? = try {
        val decimal = BigDecimal(value.trim().replace(',', '.'))
            .setScale(2, RoundingMode.UNNECESSARY)
        val minor = decimal.movePointRight(2).longValueExact()
        minor.takeIf { it >= 0L }
    } catch (_: Exception) {
        null
    }

    fun formatRub(minor: Long): String {
        require(minor >= 0L) { "Money amount must not be negative" }
        val rubles = minor / MINOR_FACTOR
        val kopecks = minor % MINOR_FACTOR
        return "${rubles},${kopecks.toString().padStart(2, '0')} ₽"
    }

    fun paymentAmount(minor: Long): String {
        require(minor > 0L) { "Payment amount must be positive" }
        val rubles = minor / MINOR_FACTOR
        val kopecks = minor % MINOR_FACTOR
        return "${rubles}.${kopecks.toString().padStart(2, '0')}"
    }

    fun wholeUnitsToMinor(units: Int): Long {
        require(units >= 0) { "Whole units must not be negative" }
        return Math.multiplyExact(units.toLong(), MINOR_FACTOR)
    }
}
