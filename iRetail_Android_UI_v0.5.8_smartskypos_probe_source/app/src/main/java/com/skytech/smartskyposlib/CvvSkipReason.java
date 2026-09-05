package com.skytech.smartskyposlib;

public enum CvvSkipReason {
    ILLEGIBLE_VALUE_ON_CARD,
    NO_VALUE_ON_CARD,
    VALUE_IS_PRESENT,
    VALUE_NOT_PROVIDED;

    public static CvvSkipReason fromString(String value) {
        if (value == null) return null;
        for (CvvSkipReason item : values()) {
            if (item.toString().equals(value)) return item;
        }
        return null;
    }
}
