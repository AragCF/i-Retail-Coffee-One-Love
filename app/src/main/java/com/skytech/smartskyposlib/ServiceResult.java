package com.skytech.smartskyposlib;
import android.os.Parcel;
import android.os.Parcelable;
public class ServiceResult extends BaseBundleParcelable {
    public ServiceResult() { super(); }
    protected ServiceResult(Parcel in) { super(in, ServiceResult.class.getClassLoader()); }
    public int getCode() { return bundle.getInt("code"); }
    public String getMessage() { return bundle.getString("message"); }
    public String getSlipBitmapName() { return bundle.getString("slipBitmapName"); }
    public String getType() { return bundle.getString("type"); }
    public static final Parcelable.Creator<ServiceResult> CREATOR = new Parcelable.Creator<ServiceResult>() {
        public ServiceResult createFromParcel(Parcel in) { return new ServiceResult(in); }
        public ServiceResult[] newArray(int size) { return new ServiceResult[size]; }
    };
}
