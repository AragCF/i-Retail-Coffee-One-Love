package com.skytech.smartskyposlib;

import android.os.Parcel;
import android.os.Parcelable;
import java.math.BigDecimal;
import java.util.UUID;

public class TransactionParams extends BaseBundleParcelable {
    public static final String AMOUNT = "amount";
    public static final String BASKET_ID = "basketId";
    public static final String CASHBACK_AMOUNT = "cashbackAmount";
    public static final String CPQR_PAYLOAD = "cpqrPayload";
    public static final String CURRENCY_CODE = "currencyCode";
    public static final String CVV = "cvv";
    public static final String CVV_SKIP_REASON = "cvvSkipReason";
    public static final String EC_AMOUNT = "ecAmount";
    public static final String EXPIRY_DATE = "expiryDate";
    public static final String EXTRA_TRANSACTION_DATA = "extraTransactionData";
    public static final String ID = "id";
    public static final String PAN = "pan";
    public static final String PAN_HASH_ALGORITHM = "panHashAlgorithm";
    public static final String PAN_HASH_KEY = "panHashKey";
    public static final String PAYLOAD = "payload";
    public static final String PAYLOAD_TYPE = "payloadType";
    public static final String PHONE_NUMBER = "phoneNumber";
    public static final String QR_ID = "QR_id";
    public static final String QR_TYPE = "QR_type";
    public static final String RECEIPT_NUMBER = "receiptNumber";
    public static final String REFERENCE_NUMBER = "referenceNumber";
    public static final String RRN = "rrn";
    public static final String TERMINAL_ID = "terminalId";
    public static final String TRANSACTION_TYPE = "transactionType";

    public TransactionParams() { super(); generateUUID(); }
    public TransactionParams(BigDecimal amount) { super(); setAmount(amount); generateUUID(); }
    public TransactionParams(String terminalId) { super(); setTerminalId(terminalId); generateUUID(); }
    public TransactionParams(String terminalId, String receiptNumber) { super(); setTerminalId(terminalId); setReceiptNumber(receiptNumber); generateUUID(); }
    public TransactionParams(BigDecimal amount, String rrn) { super(); setAmount(amount); setRrn(rrn); generateUUID(); }
    public TransactionParams(String phoneNumber, BigDecimal amount) { super(); setAmount(amount); setPhoneNumber(phoneNumber); generateUUID(); }
    protected TransactionParams(Parcel in) { super(in, TransactionParams.class.getClassLoader()); }

    private void generateUUID() { setId(UUID.randomUUID().toString().substring(0, 8)); }

    public BigDecimal getAmount() { return get(AMOUNT); }
    public void setAmount(BigDecimal v) { bundle.putSerializable(AMOUNT, v); }
    public String getBasketId() { return bundle.getString(BASKET_ID); }
    public void setBasketId(String v) { bundle.putString(BASKET_ID, v); }
    public BigDecimal getCashbackAmount() { return get(CASHBACK_AMOUNT); }
    public void setCashbackAmount(BigDecimal v) { bundle.putSerializable(CASHBACK_AMOUNT, v); }
    public String getCpqrPayload() { return bundle.getString(CPQR_PAYLOAD); }
    public void setCpqrPayload(String v) { bundle.putString(CPQR_PAYLOAD, v); }
    public String getCurrencyCode() { return bundle.getString(CURRENCY_CODE); }
    public void setCurrencyCode(String v) { bundle.putString(CURRENCY_CODE, v); }
    public String getCvv() { return bundle.getString(CVV); }
    public void setCvv(String v) { bundle.putString(CVV, v); }
    public CvvSkipReason getCvvSkipReason() { return CvvSkipReason.fromString(bundle.getString(CVV_SKIP_REASON)); }
    public void setCvvSkipReason(CvvSkipReason v) { bundle.putString(CVV_SKIP_REASON, v == null ? null : v.toString()); }
    public BigDecimal getEcAmount() { return get(EC_AMOUNT); }
    public void setEcAmount(BigDecimal v) { bundle.putSerializable(EC_AMOUNT, v); }
    public String getExpiryDate() { return bundle.getString(EXPIRY_DATE); }
    public void setExpiryDate(String v) { bundle.putString(EXPIRY_DATE, v); }
    public String getExtraTransactionData() { return bundle.getString(EXTRA_TRANSACTION_DATA); }
    public void setExtraTransactionData(String v) { bundle.putString(EXTRA_TRANSACTION_DATA, v); }
    public String getId() { return bundle.getString(ID); }
    public void setId(String v) { bundle.putString(ID, v); }
    public String getPan() { return bundle.getString(PAN); }
    public void setPan(String v) { bundle.putString(PAN, v); }
    public String getPanHashAlgorithm() { return bundle.getString(PAN_HASH_ALGORITHM); }
    public void setPanHashAlgorithm(String v) { bundle.putString(PAN_HASH_ALGORITHM, v); }
    public byte[] getPanHashKey() { return bundle.getByteArray(PAN_HASH_KEY); }
    public void setPanHashKey(byte[] v) { bundle.putByteArray(PAN_HASH_KEY, v); }
    public String getPayload() { return bundle.getString(PAYLOAD); }
    public void setPayload(String v) { bundle.putString(PAYLOAD, v); }
    public String getPayloadType() { return bundle.getString(PAYLOAD_TYPE); }
    public void setPayloadType(String v) { bundle.putString(PAYLOAD_TYPE, v); }
    public String getPhoneNumber() { return bundle.getString(PHONE_NUMBER); }
    public void setPhoneNumber(String v) { bundle.putString(PHONE_NUMBER, v); }
    public String getQrId() { return bundle.getString(QR_ID); }
    public void setQrId(String v) { bundle.putString(QR_ID, v); }
    public String getQrType() { return bundle.getString(QR_TYPE); }
    public void setQrType(String v) { bundle.putString(QR_TYPE, v); }
    public String getReceiptNumber() { return bundle.getString(RECEIPT_NUMBER); }
    public void setReceiptNumber(String v) { bundle.putString(RECEIPT_NUMBER, v); }
    public String getReferenceNumber() { return bundle.getString(REFERENCE_NUMBER); }
    public void setReferenceNumber(String v) { bundle.putString(REFERENCE_NUMBER, v); }
    public String getRrn() { return bundle.getString(RRN); }
    public void setRrn(String v) { bundle.putString(RRN, v); }
    public String getTerminalId() { return bundle.getString(TERMINAL_ID); }
    public void setTerminalId(String v) { bundle.putString(TERMINAL_ID, v); }
    public String getTransactionType() { return bundle.getString(TRANSACTION_TYPE); }
    public void setTransactionType(String v) { bundle.putString(TRANSACTION_TYPE, v); }

    public static final Parcelable.Creator<TransactionParams> CREATOR = new Parcelable.Creator<TransactionParams>() {
        public TransactionParams createFromParcel(Parcel in) { return new TransactionParams(in); }
        public TransactionParams[] newArray(int size) { return new TransactionParams[size]; }
    };
}
