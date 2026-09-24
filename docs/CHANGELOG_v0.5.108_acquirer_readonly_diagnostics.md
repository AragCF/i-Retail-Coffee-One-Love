# CHANGELOG v0.5.108 — acquirer read-only diagnostics

Дата: 24.09.2026.

После подтверждённого реального отказа `approved=false / rc=99 / amount=1.00` и read-only recovery введён текущий снимок SmartSkyPOS/acquirer-конфигурации без нового платежа.

Исторические доказательства:
- 14.09.2026 прямой локальный payment на самом Kozen, без JL22/AOA, также завершился `approved=false / rc=99 / amount=1.00`;
- TerminalData тогда показывал SmartSkyPOS `1.9.19-RC.1.11057-BETA`, профиль `VPP_BETA_TMS_V1`, TID 12000679, merchant J500523, host 185.162.94.67:9221;
- read-only история содержала также отказ `rc=99` на 57.00 ₽;
- значит AOA/JL22 не является причиной rc=99.

v0.5.108 использует уже установленный production bridge 0.5.2 и не требует обновления Kozen:
- PING;
- INFO;
- GET_STATE;
- GET_TERMINAL_DATA.

Снимок фиксирует bridge/smartsky readiness, state, TerminalData code, наличие payment route, валюту 643 и текущий TMS profile message. real POS остаётся false. Финансовых команд нет.