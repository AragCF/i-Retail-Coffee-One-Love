from pathlib import Path
import re
root = Path(__file__).resolve().parents[1]
ui = root / 'app/src/main/java/com/coffeeonelove/iretail/ui'
main = (ui / 'MainActivity.kt').read_text(encoding='utf-8')
gateway = (ui / 'IntegrationGateways.kt').read_text(encoding='utf-8')
checks = {}
for method, end, gate in [
    ('refreshCatalogFromIretail', 'refreshChannelConfigFromIretail', 'catalogReadGate'),
    ('refreshChannelConfigFromIretail', 'renderApiChanges', 'channelReadGate'),
    ('submitLoyaltyInput', 'setInterfaceLanguage', 'loyaltyReadGate'),
]:
    part = main.split('private fun ' + method + '(', 1)[1].split('private fun ' + end + '(', 1)[0]
    checks[method + ' separate result handler'] = 'apiResultHandler.post' in part and 'handler.post' not in part
    checks[method + ' owns ticket'] = gate + '.tryBegin()' in part and gate + '.complete(ticket)' in part
    checks[method + ' rejects destroyed owner'] = 'apiOwnerDestroyed' in part and 'isDestroyed' in part
checks['reset invalidates loyalty request'] = 'private fun resetToIdle() {\n        loyaltyReadGate.invalidate()' in main
checks['new screen cannot cancel API handler'] = 'loyaltyReadGate.invalidate()' in main and main.count('apiResultHandler.removeCallbacksAndMessages(null)') == 1
checks['both channel replies checked'] = '!channel.optBoolean("status", false)' in gateway and '!services.optBoolean("status", false)' in gateway
checks['services array mandatory'] = 'serviceResult.getJSONArray("services")' in gateway
checks['order ignores unconfirmed discount'] = 'val safeDiscountMinor = 0L' in gateway
checks['local bonus cap removed'] = 'bonusApplied = maxAmount.coerceAtMost' not in gateway
checks['UI discount is zero'] = 'return 0L' in main.split('private fun orderDiscountMinor()', 1)[1].split('private fun cartTotalMinor()', 1)[0]
checks['no new payment calls'] = all(x not in gateway for x in ['iretail/order/synchronize', 'iretail/payment-in/create', 'admin/device/create'])
for name, passed in checks.items():
    print(('[OK] ' if passed else '[FAIL] ') + name)
if not all(checks.values()):
    raise SystemExit('API lifecycle verification failed')
print('API_LIFECYCLE_STATIC_OK checks=' + str(len(checks)))
