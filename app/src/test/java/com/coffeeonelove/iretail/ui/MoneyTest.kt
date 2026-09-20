package com.coffeeonelove.iretail.ui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class MoneyTest {
    @Test
    fun parsesRublesWithoutLosingKopecks() {
        assertEquals(14900L, Money.parseMinor("149"))
        assertEquals(14950L, Money.parseMinor("149.50"))
        assertEquals(14999L, Money.parseMinor("149.99"))
        assertEquals(14950L, Money.parseMinor("149,50"))
    }

    @Test
    fun rejectsUnsupportedPrecisionInsteadOfRounding() {
        assertNull(Money.parseMinor("149.999"))
        assertNull(Money.parseMinor("-1.00"))
        assertNull(Money.parseMinor("not-a-price"))
    }

    @Test
    fun formatsUiAndPaymentAmountsExactly() {
        assertEquals("149,50 ₽", Money.formatRub(14950L))
        assertEquals("149.50", Money.paymentAmount(14950L))
        assertEquals(29900L, 14950L * 2L)
    }
}
