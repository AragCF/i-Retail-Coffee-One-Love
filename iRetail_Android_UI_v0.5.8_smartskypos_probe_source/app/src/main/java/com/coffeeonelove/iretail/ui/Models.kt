package com.coffeeonelove.iretail.ui

data class Product(
    val id: String,
    val offerId: String = id,
    val name: String,
    val volume: String,
    val price: Int,
    val category: String,
    val available: Boolean,
    val heat: Boolean = false,
    val gcode: String? = null,
    val imageUrl: String? = null,
    val categoryTitle: String? = null
)

data class CartLine(
    val product: Product,
    var quantity: Int = 1,
    var ownCup: Boolean = false,
    var syrupAdded: Boolean = false,
    var syrupName: String? = null
)

data class RectSpec(
    val x: Int,
    val y: Int,
    val width: Int,
    val height: Int
)

data class Hotspot(
    val label: String,
    val rect: RectSpec,
    val onTap: () -> Unit
)

data class PayMethod(
    val id: String,
    val slug: String,
    val title: String,
    val enabled: Boolean,
    val phoneRequired: Boolean
)

data class RuntimeOrder(
    val localId: String,
    val externalNumber: String,
    val amount: Int,
    val items: List<CartLine>,
    val grossAmount: Int = amount,
    val ibonusDiscountSum: Int = 0,
    val loyaltyExternalId: String? = null,
    val loyaltyBalanceLabel: String? = null,
    var status: OrderStatus = OrderStatus.CREATED,
    var paymentMethod: PaymentMethod? = null,
    var fiscalReceiptUrl: String? = null
)

data class DeviceCommandResult(
    val success: Boolean,
    val message: String,
    val percent: Int = 100
)

data class CatalogRefreshResult(
    val success: Boolean,
    val products: List<Product>,
    val message: String,
    val source: String,
    val categoriesCount: Int = 0,
    val offersCount: Int = 0,
    val channelId: String = ""
)

data class LoyaltyLookupResult(
    val success: Boolean,
    val message: String,
    val balanceLabel: String? = null,
    val rawTitle: String? = null,
    val availableBonusAmount: Int = 0,
    val externalId: String? = null,
    val couponsCount: Int = 0,
    val loyaltyActive: Boolean = false
)

enum class PaymentMethod {
    CARD,
    CASH,
    ONLINE,
    SBER_SPASIBO
}

enum class OrderStatus {
    CREATED,
    PAYMENT_STARTED,
    PAID,
    FISCALIZED,
    COOKING,
    READY,
    ERROR
}

enum class OperationResult {
    SUCCESS,
    ERROR
}

/**
 * Совместимость с ранними v0.3-архивами.
 * Если проект распаковали поверх старой папки, в дереве может остаться obsolete-файл MockGateways.kt.
 * Новый код использует OperationResult, но этот enum не даёт старому файлу ломать сборку до автоматической очистки.
 */
enum class MockResult {
    SUCCESS,
    ERROR
}
