package com.skytech.smartskyposlib;
import android.os.Parcel;
import android.os.Parcelable;
public class ReportResult extends BaseBundleParcelable {
    public ReportResult() { super(); }
    protected ReportResult(Parcel in) { super(in, ReportResult.class.getClassLoader()); }
    public int getCode() { return bundle.getInt("code"); }
    public String getMessage() { return bundle.getString("message"); }
    public String getSlip() { return bundle.getString("slip"); }
    public String getSlipBitmapName() { return bundle.getString("slipBitmapName"); }
    public static final Parcelable.Creator<ReportResult> CREATOR = new Parcelable.Creator<ReportResult>() {
        public ReportResult createFromParcel(Parcel in) { return new ReportResult(in); }
        public ReportResult[] newArray(int size) { return new ReportResult[size]; }
    };
}
