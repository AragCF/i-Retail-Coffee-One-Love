package com.coffeeonelove.iretail.pos;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

final class WireProtocolSanitizer {
    private static final Pattern SENSITIVE_FIELD =
            Pattern.compile("(?i)(payloadB64|qrPayload|payload|qrIdB64|qrId)=([^\\s]+)");

    static String safeLogLine(String line) {
        if (line == null) return "-";
        String normalized = line.replace('\n', '_').replace('\r', '_');
        Matcher matcher = SENSITIVE_FIELD.matcher(normalized);
        StringBuffer out = new StringBuffer();
        while (matcher.find()) {
            String name = matcher.group(1);
            String value = matcher.group(2);
            String replacement = name + "=[REDACTED_" + shortHash(value) + "_LEN_" + value.length() + "]";
            matcher.appendReplacement(out, Matcher.quoteReplacement(replacement));
        }
        matcher.appendTail(out);
        String result = out.toString();
        return result.length() <= 1200 ? result : result.substring(0, 1200);
    }

    static String shortHash(String value) {
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

    private WireProtocolSanitizer() {}
}
