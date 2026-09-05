package com.skytech.smartskyposlib;
import android.os.Parcel;
import android.os.Parcelable;
public class ServiceParams extends BaseBundleParcelable {
    public ServiceParams() { super(); }
    protected ServiceParams(Parcel in) { super(in, ServiceParams.class.getClassLoader()); }
    public String getExtraTransactionData() { return bundle.getString("extraTransactionData"); }
    public void setExtraTransactionData(String v) { bundle.putString("extraTransactionData", v); }
    public static final Parcelable.Creator<ServiceParams> CREATOR = new Parcelable.Creator<ServiceParams>() {
        public ServiceParams createFromParcel(Parcel in) { return new ServiceParams(in); }
        public ServiceParams[] newArray(int size) { return new ServiceParams[size]; }
    };
}
