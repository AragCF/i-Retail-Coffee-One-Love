# CHANGELOG v0.5.88 — JL22 simple cmd autoselect

Дата: 22.09.2026.

Живой v0.5.87 показал, что ADB корректно видит JL22, но PowerShell-конвейер внутри FOR/F не разбирается стабильно под cmd.exe.

v0.5.88:
- удаляет PowerShell из выбора ADB-транспорта;
- использует adb devices -l + findstr;
- принимает первое живое совпадение точной сигнатуры JL22;
- USB/Ethernet равноправны;
- финансовая и Fiscal network логика не менялась.
