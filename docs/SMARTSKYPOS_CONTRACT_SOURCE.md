# Источник SmartSkyPOS-контракта

Интеграция v0.5.8 собрана из пользовательского комплекта:

`SmartSkyPOS_Kozen_P12_Integration_Kit_v1.0(1).zip`

Целевая установленная версия:

- пакет: `com.skytech.smartskypos`;
- версия: `1.9.19-RC.1.11057`;
- versionCode: `11057`;
- устройство: Kozen P12;
- Binder descriptor: `com.skytech.smartskyposlib.ISmartSkyPos`;
- action: `com.skytech.smartskypos.ISmartSkyPos`.

AIDL и Java Parcelable-файлы были скопированы в Android-модуль без изменений.
Их хэши сверены с исходным Integration Kit при подготовке этого архива.

`SmartSkyPosGateway.kt` и диагностический экран — новый i-Retail-слой поверх этого контракта.
