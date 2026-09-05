package com.skytech.smartskyposlib;

import android.os.Parcel;
import android.os.Parcelable;
import java.math.BigDecimal;
import java.util.Date;

public class TransactionResult extends BaseBundleParcelable {
    public TransactionResult() { super(); }
    protected TransactionResult(Parcel in) { super(in, TransactionResult.class.getClassLoader()); }

    public int getCode() { return bundle.getInt("code"); }
    public String getMessage() { return bundle.getString("message"); }
    public Boolean isApproved() { return get("isApproved"); }
    public Boolean isQrTransaction() { return get("isQrTransaction"); }
    public String getRc() { return bundle.getString("rc"); }
    public String getAlternativeRc() { return bundle.getString("alternativeRc"); }
    public String getRrn() { return bundle.getString("rrn"); }
    public String getAlternativeRrn() { return bundle.getString("alternativeRrn"); }
    public String getRrnOriginal() { return bundle.getString("rrnOriginal"); }
    public String getAuthCode() { return bundle.getString("authCode"); }
    public BigDecimal getAmount() { return get("amount"); }
    public BigDecimal getAmountDiscount() { return get("amountDiscount"); }
    public BigDecimal getAmountFee() { return get("amountFee"); }
    public BigDecimal getAmountTips() { return get("amountTips"); }
    public BigDecimal getCashbackAmount() { return get("cashbackAmount"); }
    public BigDecimal getEcAmount() { return get("ecAmount"); }
    public BigDecimal getOfflineDiscountAmount() { return get("offlineDiscountAmount"); }
    public BigDecimal getOfflineFeeAmount() { return get("offlineFeeAmount"); }
    public String getCurrencyCode() { return bundle.getString("currencyCode"); }
    public String getCurrencyCaption() { return bundle.getString("currencyCaption"); }
    public Date getDatetime() { return get("datetime"); }
    public Date getDatetimeTerminal() { return get("datetimeTerminal"); }
    public String getTerminalId() { return bundle.getString("terminalId"); }
    public String getMerchantId() { return bundle.getString("merchantId"); }
    public String getReceiptNumberAsString() { Object v = bundle.get("receiptNumber"); return v == null ? null : String.valueOf(v); }
    public int getReceiptNumber() { return bundle.getInt("receiptNumber"); }
    public String getReferenceNumber() { return bundle.getString("referenceNumber"); }
    public String getId() { return bundle.getString("id"); }
    public String getType() { return bundle.getString("type"); }
    public String getName() { return bundle.getString("name"); }
    public String getPan() { return bundle.getString("pan"); }
    public String getPanHash() { return bundle.getString("panHash"); }
    public byte[] getPanSha256() { return bundle.getByteArray("panSha256"); }
    public byte[] getSha256() { return bundle.getByteArray("sha256"); }
    public String getBin() { return bundle.getString("bin"); }
    public String getCardholder() { return bundle.getString("cardholder"); }
    public String getExpirationDate() { return bundle.getString("expirationDate"); }
    public String getPaySysName() { return bundle.getString("paySysName"); }
    public String getBankName() { return bundle.getString("bankName"); }
    public String getAcquirerId() { return bundle.getString("acquirerId"); }
    public String getAcquirerName() { return bundle.getString("acquirerName"); }
    public String getAid() { return bundle.getString("aid"); }
    public String getApplicationLabel() { return bundle.getString("applicationLabel"); }
    public String getApplicationCryptogram() { return bundle.getString("applicationCryptogram"); }
    public String getApplicationCryptogramInfo() { return bundle.getString("applicationCryptogramInfo"); }
    public String getCvmResultName() { return bundle.getString("cvmResultsName"); }
    public String getCvmResultsDescription() { return bundle.getString("cvmResultsDescription"); }
    public String getPosEntryMode() { return bundle.getString("posEntryMode"); }
    public String getPosEntryModeDescription() { return bundle.getString("posEntryModeDescription"); }
    public String getKVR() { return bundle.getString("kvr"); }
    public String getTSI() { return bundle.getString("tsi"); }
    public String getTVR() { return bundle.getString("tvr"); }
    public String getPar() { return bundle.getString("par"); }
    public String getBasketId() { return bundle.getString("basketId"); }
    public String getQrId() { return bundle.getString("qrId"); }
    public String getQrMid() { return bundle.getString("qrMid"); }
    public String getQrTid() { return bundle.getString("qrTid"); }
    public String getSlip() { return bundle.getString("slip"); }
    public String getSlipCashier() { return bundle.getString("slipCashier"); }
    public String getShortSlip() { return bundle.getString("shortSlip"); }
    public String getShortSlipCashier() { return bundle.getString("shortSlipCashier"); }
    public String getSlipBitmapName() { return bundle.getString("slipBitmapName"); }
    public String getSlipBitmapCashierName() { return bundle.getString("slipBitmapCashierName"); }
    public byte[] getSlipHeader() { return bundle.getByteArray("header_bitmap"); }
    public String getExtraTransactionData() { return bundle.getString("extraTransactionData"); }

    public static final Parcelable.Creator<TransactionResult> CREATOR = new Parcelable.Creator<TransactionResult>() {
        public TransactionResult createFromParcel(Parcel in) { return new TransactionResult(in); }
        public TransactionResult[] newArray(int size) { return new TransactionResult[size]; }
    };
}
