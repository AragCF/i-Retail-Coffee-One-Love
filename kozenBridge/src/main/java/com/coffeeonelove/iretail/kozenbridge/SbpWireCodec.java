package com.coffeeonelove.iretail.kozenbridge;

import android.util.Base64;

import java.nio.charset.StandardCharsets;

final class SbpWireCodec {
    private static final int MAX_RAW_LENGTH = 4096;

    static String encode(String value) {
        if (value == null) return "";
        byte[] raw = value.getBytes(StandardCharsets.UTF_8);
        if (raw.length > MAX_RAW_LENGTH) throw new IllegalArgumentException("payload too long");
        return Base64.encodeToString(raw, Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING);
    }

    static String decode(String encoded) {
        if (encoded == null || encoded.isEmpty()) return "";
        byte[] raw = Base64.decode(encoded, Base64.URL_SAFE | Base64.NO_WRAP | Base64.NO_PADDING);
        if (raw.length > MAX_RAW_LENGTH) throw new IllegalArgumentException("payload too long");
        return new String(raw, StandardCharsets.UTF_8);
    }

    static boolean validEncoded(String encoded) {
        if (encoded == null || encoded.isEmpty() || encoded.length() > 8192) return false;
        try {
            decode(encoded);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private SbpWireCodec() {}
}
