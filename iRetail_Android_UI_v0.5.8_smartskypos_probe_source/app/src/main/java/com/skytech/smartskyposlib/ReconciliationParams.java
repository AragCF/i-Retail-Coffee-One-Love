package com.skytech.smartskyposlib;
import android.os.Parcel;
import android.os.Parcelable;
public class ReconciliationParams extends BaseBundleParcelable {
    public ReconciliationParams() { super(); }
    public ReconciliationParams(String terminalId) { super(); setTerminalId(terminalId); }
    protected ReconciliationParams(Parcel in) { super(in, ReconciliationParams.class.getClassLoader()); }
    public String getTerminalId() { return bundle.getString("terminalId"); }
    public void setTerminalId(String v) { bundle.putString("terminalId", v); }
    public String getExtraTransactionData() { return bundle.getString("extraTransactionData"); }
    public void setExtraTransactionData(String v) { bundle.putString("extraTransactionData", v); }
    public static final Parcelable.Creator<ReconciliationParams> CREATOR = new Parcelable.Creator<ReconciliationParams>() {
        public ReconciliationParams createFromParcel(Parcel in) { return new ReconciliationParams(in); }
        public ReconciliationParams[] newArray(int size) { return new ReconciliationParams[size]; }
    };
}
