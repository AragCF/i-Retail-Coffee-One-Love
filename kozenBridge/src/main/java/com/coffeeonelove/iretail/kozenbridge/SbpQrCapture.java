package com.coffeeonelove.iretail.kozenbridge;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayDeque;

final class SbpQrCapture {
    static final int MAX_EVENTS = 16;

    enum AckStatus { ACKED, ALREADY_ACKED, EMPTY, HEAD_MISMATCH }

    static final class Event {
        final long sequence;
        final String qrId;
        final String payload;
        final long capturedAtMs;
        final String source;

        Event(long sequence, String qrId, String payload, long capturedAtMs, String source) {
            this.sequence = sequence;
            this.qrId = qrId;
            this.payload = payload;
            this.capturedAtMs = capturedAtMs;
            this.source = source;
        }

        SafeSummary safeSummary() {
            return summarize(sequence, qrId, payload, capturedAtMs, source);
        }
    }

    static final class SafeSummary {
        final long sequence;
        final String qrIdHash;
        final String payloadHash;
        final int payloadLength;
        final long capturedAtMs;
        final String source;

        SafeSummary(long sequence, String qrIdHash, String payloadHash, int payloadLength,
                    long capturedAtMs, String source) {
            this.sequence = sequence;
            this.qrIdHash = qrIdHash;
            this.payloadHash = payloadHash;
            this.payloadLength = payloadLength;
            this.capturedAtMs = capturedAtMs;
            this.source = source;
        }
    }

    private final ArrayDeque<Event> queue = new ArrayDeque<>();
    private long nextSequence = 1L;
    private long droppedCount = 0L;
    private long lastAckedSequence = 0L;

    synchronized Event capture(String qrId, String payload) {
        return capture(qrId, payload, "callback");
    }

    synchronized Event capture(String qrId, String payload, String source) {
        if (queue.size() >= MAX_EVENTS) {
            queue.removeFirst();
            droppedCount++;
        }
        Event event = new Event(nextSequence++, qrId, payload, System.currentTimeMillis(), normalizeSource(source));
        queue.addLast(event);
        return event;
    }

    synchronized Event peek() { return queue.peekFirst(); }

    synchronized AckStatus ack(long sequence) {
        if (sequence > 0L && sequence == lastAckedSequence) return AckStatus.ALREADY_ACKED;
        Event head = queue.peekFirst();
        if (head == null) return AckStatus.EMPTY;
        if (sequence <= 0L || head.sequence != sequence) return AckStatus.HEAD_MISMATCH;
        queue.removeFirst();
        lastAckedSequence = sequence;
        return AckStatus.ACKED;
    }

    synchronized long headSequence() {
        Event head = queue.peekFirst();
        return head == null ? 0L : head.sequence;
    }

    synchronized int size() { return queue.size(); }
    synchronized long droppedCount() { return droppedCount; }
    synchronized Event take() { return queue.pollFirst(); }
    synchronized void clear() { queue.clear(); }

    static SafeSummary summarize(String qrId, String payload, long capturedAtMs) {
        return summarize(0L, qrId, payload, capturedAtMs, "callback");
    }

    static SafeSummary summarize(long sequence, String qrId, String payload, long capturedAtMs, String source) {
        return new SafeSummary(sequence, shortHash(qrId), shortHash(payload),
                payload == null ? 0 : payload.length(), capturedAtMs, normalizeSource(source));
    }

    private static String normalizeSource(String source) {
        if (source == null || source.isEmpty()) return "unknown";
        return source.replace(' ', '_').replace('\n', '_').replace('\r', '_');
    }

    private static String shortHash(String value) {
        if (value == null || value.isEmpty()) return "-";
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder sb = new StringBuilder(16);
            for (int i = 0; i < 8 && i < digest.length; i++) sb.append(String.format("%02x", digest[i] & 0xff));
            return sb.toString();
        } catch (Exception e) {
            return "hash_error";
        }
    }
}
