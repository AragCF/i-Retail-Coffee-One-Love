package com.skytech.smartskyposlib;

interface TransactionCallback {
    void onStateChanged(int state, String message);
    void onQrReading(String qrId, String qrPayload);

    // Reserved transaction slot #3 from an older contract revision.
    // Never call directly. It exists only to preserve Binder transaction numbers.
    void reserved3();

    void onOperationNameChanged(String operationName);
    String onRequestPassword(String prompt);
}
