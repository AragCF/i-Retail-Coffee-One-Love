# Coffee One Love — Vendotek VT / VTK integration plan

Дата: 15.09.2026  
Ветка: `v0.5.23-vendotek-discovery`  
Статус: старт практической интеграции после фиксации результата Kozen.

## 1. Источник протокола

Основной источник на этом этапе: `VTK_ руководство_по_работе.pdf`, индекс `VTK-MAN-RU`, версия 1.0, дата 19.01.2026.

Эта версия документа новее раннего архитектурного DRAFT проекта и имеет приоритет для деталей wire-протокола.

## 2. Роль i-Retail

Основной `i-Retail UI` остаётся на JL22 под Android 6. Для Vendotek приложение выступает логическим VMC (Vending Machine Controller).

Vendotek реализуется отдельным адаптером и не использует Kozen Binder/AOA bridge.

Общий верхний контракт остаётся единым:

```text
Order / Checkout
       |
Payment Coordinator
       |
       +-- Kozen adapter
       |
       +-- Vendotek VTK adapter
```

На конкретной машине активен один выбранный POS-провайдер.

## 3. Транспорт VTK

VTK является прикладным протоколом между POS и VMC и поддерживает:

- последовательный канал RS-232;
- TCP/IP.

Для последовательного канала значения по умолчанию:

```text
115200 bit/s
8N1
flow control: none
```

Для TCP/IP POS по умолчанию использует порт `62801`, а VMC открывает соединение с IP/портом POS.

Для нашего физического комплекта первым целевым вариантом остаётся USB/virtual COM, но конкретный Android USB serial driver нельзя выбирать до чтения реальных USB descriptors Vendotek.

## 4. Serial frame

Формат последовательного VTK frame:

```text
0x1F                         start byte
length: 2 bytes              length of following data, excluding CRC16
0x96FB                       discriminator VMC -> POS
or 0x97FB                    discriminator POS -> VMC
BER-TLV application payload
CRC16-CCITT                  init 0xFFFF
```

CRC вычисляется по frame от стартового `0x1F` до последнего байта payload включительно, без двух байт самого CRC. Это подтверждается опубликованными в руководстве эталонными hex-векторами.

После первого байта `0x1F` оставшаяся часть сообщения должна быть принята не позднее 8 секунд.

## 5. Минимальные команды первой реализации

### IDL

Переводит стороны из INACTIVE в IDLE и поддерживает рабочую сессию.

Первое IDL для VTKPOS-V1 требует корректного локального времени; для EftVending/VTKPOS-V2 оно может быть опциональным. До определения ПО фактического Vendotek будем передавать синхронизированное локальное время безопасно и явно.

### VRP

Запрос продажи. Обязательные для нашего MVP данные:

- operation number, tag `0x03`;
- amount in minor currency units, tag `0x04`.

Ответ VRP:

- ненулевая сумма = операция одобрена;
- нулевая сумма = операция отклонена.

### FIN

После одобрения VRP i-Retail не считает Vendotek-операцию полностью завершённой до фактического результата выдачи напитка.

После выдачи:

- успешная выдача -> FIN с подтверждённой суммой;
- неуспешная выдача -> FIN с нулевой суммой согласно VTK.

Только подтверждённый ответ FIN завершает Vendotek-сценарий.

### ABR

Допускается для прерывания ожидания после VRP и до окончательного ответа, но протокол прямо предупреждает: ABR не гарантирует отмену, если банковская транзакция уже началась. Поэтому ABR не может использоваться как доказательство финансовой отмены без ответа терминала/банковского сценария.

## 6. Operation number и защита от дублей

Перед новым VRP VMC увеличивает operation number и сохраняет его.

Ключевое свойство VTK: если POS получает повторный VRP/CDP/CRD или FIN с тем же operation number, он должен трактовать его как повтор и возвращать предыдущий результат.

Поэтому mapping i-Retail должен быть долговечным:

```text
order_id
payment_attempt_id
provider=VENDOTEK
vtk_operation_number
amount_minor
last_confirmed_phase
```

После перезапуска/обрыва новый operation number для незавершённой попытки автоматически не создаётся.

## 7. Внутренние состояния i-Retail для Vendotek

```text
DISCONNECTED
READY
PAYMENT_IN_PROGRESS
PAYMENT_APPROVED_AWAITING_VEND_RESULT
COMPLETED
DECLINED
CANCELLED
UNKNOWN
ERROR
```

`PAYMENT_APPROVED_AWAITING_VEND_RESULT` является обязательным отличием Vendotek: ненулевая сумма в ответе VRP ещё не означает, что vending operation полностью завершена.

## 8. Safe recovery

При USB detach, timeout или рестарте приложения:

- финансовая попытка не повторяется автоматически;
- сохраняется operation number;
- после восстановления транспорта сначала восстанавливается IDL/session;
- повтор сообщения с тем же operation number используется только в соответствии с VTK repeat semantics;
- неоднозначный результат остаётся `UNKNOWN`, пока не получено достоверное подтверждение.

## 9. Безопасные system-info возможности

Если фактическое ПО Vendotek поддерживает уровень F2, протокол определяет read-only system-info запросы:

- `STATUS` — READY / NOT_READY / DISABLED / BUSY и причины;
- `POS_PARAMS` — версия ПО, serial, TID, VTK mode;
- `BANK_PARAMS` — provider/acquirer;
- `NET_PARAMS` — сетевой канал.

Эти запросы будут использоваться после первого успешного IDL smoke test и только если конкретный терминал сообщает поддержку соответствующей функциональности.

## 10. Первый практический этап

До реализации USB serial transport необходимо получить фактические данные подключённого Vendotek на JL22:

- VID/PID;
- device class/subclass/protocol;
- interface class/subclass/protocol;
- endpoints;
- kernel driver binding;
- наличие `/dev/ttyACM*`, `/dev/ttyUSB*` или иного tty;
- manufacturer/product/serial strings;
- USB speed и topology.

Для этого создан `VENDOTEK_01_USB_DISCOVERY.bat`.

Этот сценарий не отправляет VTK, не запускает оплату и не меняет настройки терминала.

## 11. Следующий этап после USB discovery

После получения descriptors:

1. выбрать минимальный Android 6 transport driver;
2. реализовать `VendotekUsbTransport`;
3. реализовать VTK frame/TLV/CRC codec;
4. прогнать published hex vectors из `VTK-MAN-RU 1.0`;
5. открыть serial link без финансовых команд;
6. выполнить IDL;
7. при поддержке F2 запросить STATUS/POS_PARAMS/BANK_PARAMS/NET_PARAMS;
8. только после этого готовить staged VRP test с ручным разрешением оператора.

## 12. Что пока сознательно не делаем

- Multicard / Узбекистан;
- реальную Vendotek продажу до подтверждения транспорта и IDL;
- FIN/ABR финансовые сценарии до тестового контура;
- фискализацию через Vendotek;
- QR/SBP через Vendotek;
- Mifare/NFCReader;
- settlement и прочие F3+ операции.

## 13. Критерий завершения v0.5.23 discovery

Этап считается завершённым, когда на реальном JL22 однозначно известны USB descriptors и способ доступа к последовательному VTK-каналу Vendotek. После этого новая ветка переводится из hardware discovery в implementation transport/codec.
