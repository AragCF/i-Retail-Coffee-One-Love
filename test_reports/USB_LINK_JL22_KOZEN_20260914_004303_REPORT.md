# USB live-link probe: JL22 ↔ Kozen P12

Date/time of captured run: 2026-09-14 00:43–00:53 local time.

Source archive supplied from the Windows test stand:

- `USB_LINK_JL22_KOZEN_20260914_004303.zip`
- SHA-256: `f09c8ac79be628605785f5dec2cd01d204d491e9fb8809ed507d994c12c7d86e`

## Result

The first physical JL22-host ↔ Kozen-device connection did **not** enumerate Kozen on the JL22 USB bus.

This corrects the earlier working assumption that the physical link had already been validated. The capability probes still show that the architecture is plausible (JL22 has USB host support; Kozen can operate as a USB device), but this particular cable/port/live-link run did not produce a new USB device on JL22.

## Evidence

`DIFF_01_dumpsys_usb.txt`:

```text
FC: no differences encountered
```

`DIFF_02_usb_sysfs.txt`:

```text
FC: no differences encountered
```

The JL22 USB host state after connection still contains only the already-present Realtek USB 10/100 LAN adapter:

```text
/dev/bus/usb/001/003
Vendor ID: 0bda
Product ID: 8152
Manufacturer: Realtek
Product: USB 10/100 LAN
```

`lsusb` after the connection contains only:

```text
Bus 001 Device 002: ID 05e3:0608
Bus 001 Device 001: ID 1d6b:0002
Bus 002 Device 001: ID 1d6b:0001
Bus 003 Device 001: ID 1d6b:0001
Bus 001 Device 003: ID 0bda:8152
```

There is no newly enumerated Kozen USB VID/PID in the AFTER snapshot.

The only meaningful BEFORE/AFTER changes are normal traffic counters on existing network interfaces (`lo` and `eth0`); they do not indicate a new USB network device.

## Current conclusion

- JL22 USB host stack is alive and already enumerates other USB hardware (Realtek 0bda:8152).
- The selected JL22 ↔ Kozen physical connection did not reach normal USB enumeration.
- Therefore AOA, RNDIS, USB serial, or any higher-level USB protocol cannot yet be tested over this connection.
- The next step is a dual-sided physical-link diagnosis, preferably keeping ADB access to JL22 over Ethernet and ADB access to Kozen over TCP/Wi-Fi while the devices are physically connected to each other.

## Next diagnostic target

Capture both sides simultaneously during cable insertion and determine:

1. whether Kozen detects VBUS / a USB host;
2. whether Kozen changes USB device state or functions;
3. whether JL22 kernel reports connect/reset/enumeration errors on the relevant host controller;
4. whether another JL22 USB host port or cable enumerates Kozen;
5. only after successful enumeration, continue with AOA transport probing.
