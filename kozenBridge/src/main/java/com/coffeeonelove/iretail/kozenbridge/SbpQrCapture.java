package com.coffeeonelove.iretail.kozenbridge;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

final class SbpQrCapture {
    static final class Event {
        final String qrId;
        final String payload;
        final long capturedAtMs;

        Event(String qrId, String payload, long capturedAtMs) {
            this.qrId = qrId;
            this.payload = payload;
            this.capturedAtMs = capturedAtMs;
        }

        SafeSummary safeSummary() {
            return summarize(qrId, payload, capturedAtMs);
        }
    }

    static final class SafeSummary {
        final String qrIdHash;
        final String payloadHash;
        final int payloadLength;
        final long capturedAtMs;

        SafeSummary(String qrIdHash, String payloadHash, int payloadLength, long capturedAtMs) {
            this.qrIdHash = qrIdHash;
            this.payloadHash = payloadHash;
            this.payloadLength = payloadLength;
            this.capturedAtMs = capturedAtMs;
        }
    }

    private Event current;

    synchronized Event capture(String qrId, String payload) {
        current = new Event(qrId, payload, System.currentTimeMillis());
        return current;
    }

    synchronized Event peek() {
        return current;
    }

    synchronized Event take() {
        Event value = current;
        current = null;
        return value;
    }

    synchronized void clear() {
        current = null;
    }

    static SafeSummary summarize(String qrId, String payload, long capturedAtMs) {
        return new SafeSummary(
                shortHash(qrId),
                shortHash(payload),
                payload == null ? 0 : payload.length(),
                capturedAtMs
        );
    }

    private static String shortHash(String value) {
        if (value == null || value.isEmpty()) return "-";
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256")
                    .digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(16);
            for (int i = 0; i < 8 && i < digest.length; i++) {
                sb.append(String.format("%02x", digest[i] & 0xff));
            }
            return sb.toString();
        } catch (Exception e) {
            return "hash_error";
        }
    }
}
