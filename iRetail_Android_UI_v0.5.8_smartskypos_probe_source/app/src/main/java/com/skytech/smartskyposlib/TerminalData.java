package com.skytech.smartskyposlib;
import android.os.Parcel;
import android.os.Parcelable;
import java.util.ArrayList;
public class TerminalData extends BaseBundleParcelable {
    public TerminalData() { super(); }
    protected TerminalData(Parcel in) { super(in, TerminalData.class.getClassLoader()); bundle.setClassLoader(TerminalData.class.getClassLoader()); }
    public int getCode() { return bundle.getInt("code"); }
    public String getMessage() { return bundle.getString("message"); }
    public String getMerchantId() { return bundle.getString("merchantId"); }
    public String getSerialNumber() { return bundle.getString("serialNumber"); }
    public String getTerminalId() { return bundle.getString("terminalId"); }
    public String getTmsId() { return bundle.getString("tmsId"); }
    @SuppressWarnings("unchecked") public ArrayList<Terminal> getTerminals() { return (ArrayList<Terminal>) bundle.get("terminals"); }
    public static final Parcelable.Creator<TerminalData> CREATOR = new Parcelable.Creator<TerminalData>() {
        public TerminalData createFromParcel(Parcel in) { return new TerminalData(in); }
        public TerminalData[] newArray(int size) { return new TerminalData[size]; }
    };
}
