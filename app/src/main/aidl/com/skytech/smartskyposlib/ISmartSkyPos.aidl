package com.skytech.smartskyposlib;

import com.skytech.smartskyposlib.TransactionParams;
import com.skytech.smartskyposlib.TransactionResult;
import com.skytech.smartskyposlib.TransactionCallback;
import com.skytech.smartskyposlib.StateCallback;
import com.skytech.smartskyposlib.ReconciliationParams;
import com.skytech.smartskyposlib.ReconciliationResult;
import com.skytech.smartskyposlib.ReportResult;
import com.skytech.smartskyposlib.ServiceParams;
import com.skytech.smartskyposlib.ServiceResult;
import com.skytech.smartskyposlib.TerminalData;

interface ISmartSkyPos {
    // Binder transaction #1
    int getState();
    // #2
    void registerStateCallback(StateCallback callback);
    // #3
    void unregisterStateCallback(StateCallback callback);
    // #4
    TerminalData getTerminalData();
    // #5
    TransactionResult payment(in TransactionParams params, TransactionCallback callback);
    // #6
    TransactionResult cancel(in TransactionParams params, TransactionCallback callback);
    // #7
    TransactionResult cancelLast(in TransactionParams params, TransactionCallback callback);
    // #8
    TransactionResult refund(in TransactionParams params, TransactionCallback callback);
    // #9
    ServiceResult initialization();
    // #10
    ServiceResult activation();
    // #11
    ServiceResult testHostConnection(in ServiceParams params);
    // #12
    boolean cancelCardReading();
    // #13
    ReconciliationResult reconciliation(in ReconciliationParams params);
    // #14
    ReportResult report();
    // #15
    ReportResult fullReport();
    // #16
    ServiceResult serviceMenu();
    // #17
    TransactionResult preAuth(in TransactionParams params, TransactionCallback callback);
    // #18
    TransactionResult preAuthConfirm(in TransactionParams params, TransactionCallback callback);
    // #19
    TransactionResult qrPayment(in TransactionParams params, TransactionCallback callback);
    // #20
    TransactionResult getLastTransaction(in TransactionParams params);
    // #21
    TransactionResult getTransaction(in TransactionParams params);
    // #22
    TransactionResult ecomPayment(in TransactionParams params, TransactionCallback callback);
    // #23
    TransactionResult qrRefund(in TransactionParams params, TransactionCallback callback);
    // #24
    TransactionResult b2cCardTransfer(in TransactionParams params, TransactionCallback callback);
    // #25
    TransactionResult readCardDetails(in TransactionParams params, TransactionCallback callback);
    // #26
    TransactionResult ecPurchase(in TransactionParams params, TransactionCallback callback);
    // #27
    TransactionResult ecRefund(in TransactionParams params, TransactionCallback callback);
    // #28
    TransactionResult balance(in TransactionParams params, TransactionCallback callback);
    // #29
    TransactionResult cashIn(in TransactionParams params, TransactionCallback callback);
    // #30
    TransactionResult cashOut(in TransactionParams params, TransactionCallback callback);

    // Binder slots #31 and #32 are absent from SmartSkyPOS 1.9.19-RC.1.11057.
    // They are retained here only so generated Stub/Proxy transaction IDs remain exact.
    void reserved31();
    void reserved32();

    // #33
    TransactionResult setPin(in TransactionParams params, TransactionCallback callback);
    // #34
    TransactionResult changePin(in TransactionParams params, TransactionCallback callback);
    // #35
    TransactionResult purchaseWithCashback(in TransactionParams params, TransactionCallback callback);
    // #36
    TransactionResult unreferencedRefund(in TransactionParams params, TransactionCallback callback);
    // #37
    TransactionResult preAuthCancel(in TransactionParams params, TransactionCallback callback);
    // #38
    TransactionResult payerDetails(in TransactionParams params, TransactionCallback callback);
    // #39
    TransactionResult preAuthIncrement(in TransactionParams params, TransactionCallback callback);

    // Binder slot #40 is absent from this build; preserve numbering only.
    void reserved40();

    // #41
    TransactionResult qrCancel(in TransactionParams params, TransactionCallback callback);
}
