package com.skytech.smartskyposlib;
import android.os.Parcel;
import android.os.Parcelable;
import java.util.ArrayList;
import java.util.Date;
public class ReconciliationResult extends BaseBundleParcelable {
    public ReconciliationResult() { super(); }
    protected ReconciliationResult(Parcel in) { super(in, ReconciliationResult.class.getClassLoader()); }
    public int getCode() { return bundle.getInt("code"); }
    public String getMessage() { return bundle.getString("message"); }
    public Boolean isApproved() { return get("isApproved"); }
    public Boolean isConfigurationUpdated() { return get("isConfigurationUpdated"); }
    public String getRc() { return bundle.getString("rc"); }
    public String getRrn() { return bundle.getString("rrn"); }
    public Date getDatetime() { return get("datetime"); }
    public String getSlip() { return bundle.getString("slip"); }
    public String getSlipBitmapName() { return bundle.getString("slipBitmapName"); }
    @SuppressWarnings("unchecked") public ArrayList<TransactionResult> getTransactionLog() { return (ArrayList<TransactionResult>) bundle.get("transactionLog"); }
    public static final Parcelable.Creator<ReconciliationResult> CREATOR = new Parcelable.Creator<ReconciliationResult>() {
        public ReconciliationResult createFromParcel(Parcel in) { return new ReconciliationResult(in); }
        public ReconciliationResult[] newArray(int size) { return new ReconciliationResult[size]; }
    };
}
