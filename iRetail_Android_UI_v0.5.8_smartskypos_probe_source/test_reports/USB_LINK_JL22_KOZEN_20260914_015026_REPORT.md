# USB live-link probe after replacing the Kozen power/data cable

Captured: 2026-09-14 01:50–01:53 local time.

Source archive:

- `USB_LINK_JL22_KOZEN_20260914_015026.zip`
- SHA-256: `17402bed65c0f559ef337b595063980243f43d4541580892fff32b11dd608361`

## Important correction

This run did **not** probe JL22 as intended. `USB_08_LIVE_LINK_PROBE.bat` used unqualified `adb` commands. At the time of the run Windows ADB selected the network-connected Kozen endpoint instead of JL22.

Evidence from `BEFORE_01_identity.txt` / `AFTER_01_identity.txt`:

```text
192.168.31.134:5555    device product:D1 model:P12 device:D1
Kozen
P12
Android 11 / API 30
mt6761
```

Therefore the BEFORE/AFTER diff in this archive must not be interpreted as a JL22 host-bus comparison.

## What this run does confirm

After replacing the long cable with the shorter stable cable, Kozen is alive and its USB device side reports a fully configured connection:

```text
connected=true
configured=true
current_mode=ufp
power_role=sink
data_role=device
kernel_state=CONFIGURED
```

USB properties on Kozen also show:

```text
persist.sys.usb.config=adb
sys.usb.config=adb
sys.usb.state=adb
sys.usb.configfs=1
sys.usb.controller=musb-hdrc
```

This is a materially better result than the unstable long-cable run. It indicates that Kozen now sees VBUS/a USB host and reaches the configured USB-device state instead of rebooting from insufficient power.

The first commands of the BEFORE phase briefly returned `device offline` / `error: closed`, then the same Kozen TCP ADB endpoint recovered and the AFTER phase completed normally. Because this probe accidentally targeted Kozen, this transient must not be used as evidence about JL22 enumeration.

## Current conclusion

- The long cable was a genuine power-integrity problem.
- The shorter cable stabilizes Kozen.
- Kozen now reaches USB `CONFIGURED` as a UFP/device and power sink.
- We still need a host-side snapshot from JL22 to identify the Kozen VID/PID and confirm exactly what JL22 enumerated.
- The old `USB_08_LIVE_LINK_PROBE.bat` is unsuitable once more than one Android device is reachable over ADB because it does not pin the ADB serial.

## Next step

Use `USB_09_DUAL_SIDE_LINK_PROBE.bat` from branch `v0.5.12-usb-dual-side-probe`.

The new probe explicitly selects:

- JL22 by `model:M190` (or an explicit ADB serial);
- Kozen by `model:P12` (or an explicit ADB serial).

It captures both devices simultaneously without changing USB settings. If JL22 confirms Kozen enumeration, the next implementation step is the first Android Open Accessory host handshake and Kozen payment-bridge transport prototype.
