#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CLIENT = ROOT / "app/src/main/java/com/coffeeonelove/iretail/pos/KozenAoaPaymentClient.java"

old = '''        if (!unresolved.isEmpty()) {
            notifyStatus(listener, "Проверяем незавершённую оплату " + unresolved + "…");
            try {
                ensureLink();
                verifyBridge();
                PaymentResult recovered = queryPaymentStatus(unresolved);
                Log.w(TAG, "UNRESOLVED_STATUS_RECOVERY requestId=" + unresolved + " status=" + recovered.status +
                        " code=" + recovered.code + " noPaymentSent=true");
                if (recovered.isFinal()) clearUnresolved();
                deliverResult(listener, recovered.isFinal() ? recovered : PaymentResult.local(
                        unresolved, "UNCERTAIN_RECOVERY_REQUIRED", "PREVIOUS_UNRESOLVED",
                        "Предыдущая оплата остаётся неопределённой. Новый платёж заблокирован."));
            } catch (Exception e) {
                closeLink();
                deliverResult(listener, PaymentResult.local(
                        unresolved, "UNCERTAIN_RECOVERY_REQUIRED", "RECOVERY_FAILED",
                        "Не удалось проверить предыдущую оплату: " + safe(e.getMessage())));
            }
            return;
        }
'''

new = '''        if (!unresolved.isEmpty()) {
            notifyStatus(listener, "Проверяем незавершённую оплату " + unresolved + "…");
            try {
                ensureLink();
                verifyBridge();
                PaymentResult recovered = queryPaymentStatus(unresolved);
                Log.w(TAG, "UNRESOLVED_STATUS_RECOVERY requestId=" + unresolved + " status=" + recovered.status +
                        " code=" + recovered.code + " noPaymentSent=true");

                // A recovered payment belongs to the PREVIOUS UI attempt. It must never be
                // treated as approval for the order that happens to be on screen now.
                if (recovered.isApproved()) {
                    // Keep the recovery lock. The financial result is known, but the matching
                    // application order must be recovered explicitly before a new charge is allowed.
                    deliverResult(listener, PaymentResult.local(
                            unresolved, "UNCERTAIN_RECOVERY_REQUIRED", "PREVIOUS_APPROVED_ORDER_RECOVERY",
                            "Предыдущая оплата одобрена. Новый платёж заблокирован до восстановления предыдущего заказа."));
                    return;
                }

                if (recovered.isDeclined() || "FAILED".equals(recovered.status) || "BLOCKED".equals(recovered.status)) {
                    // Definite no-charge outcome: unlock future payments, but do not continue the
                    // current click automatically. A second deliberate tap gets a new requestId.
                    clearUnresolved();
                    deliverResult(listener, PaymentResult.local(
                            unresolved, "BLOCKED", "PREVIOUS_RESOLVED_NO_CHARGE",
                            "Предыдущая операция завершена без списания. Текущий платёж не отправлялся; нажмите оплатить ещё раз."));
                    return;
                }

                deliverResult(listener, PaymentResult.local(
                        unresolved, "UNCERTAIN_RECOVERY_REQUIRED", "PREVIOUS_UNRESOLVED",
                        "Предыдущая оплата остаётся неопределённой. Новый платёж заблокирован."));
            } catch (Exception e) {
                closeLink();
                deliverResult(listener, PaymentResult.local(
                        unresolved, "UNCERTAIN_RECOVERY_REQUIRED", "RECOVERY_FAILED",
                        "Не удалось проверить предыдущую оплату: " + safe(e.getMessage())));
            }
            return;
        }
'''

text = CLIENT.read_text(encoding="utf-8")
if new in text:
    print("[OK] prior-payment recovery safety already applied")
elif old in text:
    CLIENT.write_text(text.replace(old, new, 1), encoding="utf-8", newline="\n")
    print("[OK] prior-payment recovery can no longer approve the current order")
else:
    raise SystemExit("[ERROR] expected recovery block not found")

print("[SUCCESS] v0.5.20 recovery safety hardened")
