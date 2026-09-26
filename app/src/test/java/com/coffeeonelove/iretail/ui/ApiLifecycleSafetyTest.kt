package com.coffeeonelove.iretail.ui

import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.Callable
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

class ApiLifecycleSafetyTest {
    @Test fun parallelReadDoesNotStart() {
        val gate = ApiRequestGate()
        val ticket = gate.tryBegin()!!
        assertNull(gate.tryBegin())
        assertTrue(gate.complete(ticket))
        assertNotNull(gate.tryBegin())
    }
    @Test fun oldSessionCannotApplyOrOverlap() {
        val gate = ApiRequestGate()
        val ticket = gate.tryBegin()!!
        gate.invalidate()
        assertNull(gate.tryBegin())
        assertFalse(gate.complete(ticket))
        val next = gate.tryBegin()!!
        assertFalse(gate.complete(ticket))
        assertNull(gate.tryBegin())
        assertTrue(gate.complete(next))
    }
    @Test fun destroyedOwnerRejectsResult() {
        val gate = ApiRequestGate()
        val ticket = gate.tryBegin()!!
        gate.close()
        assertFalse(gate.complete(ticket))
        assertNull(gate.tryBegin())
    }
    @Test fun duplicateOrForeignCallbackCannotFreeSlot() {
        val gate = ApiRequestGate()
        val ticket = gate.tryBegin()!!
        assertFalse(gate.complete(ticket + 1))
        assertNull(gate.tryBegin())
        assertTrue(gate.complete(ticket))
        assertFalse(gate.complete(ticket))
    }
    @Test fun concurrentAttemptsHaveOneWinner() {
        val gate = ApiRequestGate()
        val pool = Executors.newFixedThreadPool(8)
        try {
            val results = (1..64).map { pool.submit(Callable { gate.tryBegin() }) }
            assertEquals(1, results.count { it.get(5, TimeUnit.SECONDS) != null })
        } finally { pool.shutdownNow() }
    }
    private fun client() = LoyaltyLookupResult(
        true, "Synthetic client", balanceLabel = "1000 test points",
        availableBonusAmount = 1000, externalId = "synthetic-client", loyaltyActive = true
    )
    @Test fun availableBalanceDoesNotAuthorizeRedemption() {
        val gateway = LocalLoyaltyGateway()
        gateway.loginSuccess(client())
        for (amount in listOf(-1, 0, 10, 1000, Int.MAX_VALUE)) {
            assertEquals(0, gateway.applyBonus(amount))
            assertEquals(0, gateway.bonusApplied)
        }
        assertTrue(gateway.attachedToOrder)
        assertEquals("synthetic-client", gateway.externalId)
    }
    @Test fun failedLookupCannotAttachClient() {
        val gateway = LocalLoyaltyGateway()
        gateway.loginSuccess(client())
        gateway.loginSuccess(client().copy(success = false))
        assertFalse(gateway.loggedIn)
        assertFalse(gateway.attachedToOrder)
        assertNull(gateway.externalId)
    }
    @Test fun disabledProgramCannotAttachClient() {
        val gateway = LocalLoyaltyGateway()
        gateway.loginSuccess(client().copy(loyaltyActive = false))
        assertFalse(gateway.loggedIn)
        assertEquals(0, gateway.applyBonus(100))
    }
    @Test fun orderGatewayCannotAcceptInventedBonusDiscount() {
        val gateway = LocalRetailOrderGateway()
        val product = Product("test", name = "Synthetic coffee", volume = "200ml",
            price = 123, category = "coffee", available = true, priceMinor = 12345L)
        val line = CartLine(product)
        for (discount in listOf(-1L, 0L, 50L, 12345L, Long.MAX_VALUE)) {
            val order = gateway.createOrder(listOf(line), 12345L, discount)
            assertEquals(12345L, order.amountMinor)
            assertEquals(12345L, order.grossAmountMinor)
            assertEquals(0L, order.ibonusDiscountMinor)
            assertEquals(0, order.ibonusDiscountSum)
        }
    }
    @Test fun clearingClientRemovesIdentity() {
        val gateway = LocalLoyaltyGateway()
        gateway.loginSuccess(client())
        gateway.clear()
        assertFalse(gateway.loggedIn)
        assertNull(gateway.externalId)
        assertNull(gateway.balanceLabel)
        assertEquals(0, gateway.bonusApplied)
    }
}
