package com.skytech.smartskyposlib;
import android.os.Parcel;
import android.os.Parcelable;
public class Currency extends BaseBundleParcelable {
    public Currency() { super(); }
    protected Currency(Parcel in) { super(in, Currency.class.getClassLoader()); }
    public String getCurrencyCaption() { return bundle.getString("currencyCaption"); }
    public String getCurrencyCode() { return bundle.getString("currencyCode"); }
    public int getCurrencyExponent() { return bundle.getInt("currencyExponent"); }
    public static final Parcelable.Creator<Currency> CREATOR = new Parcelable.Creator<Currency>() {
        public Currency createFromParcel(Parcel in) { return new Currency(in); }
        public Currency[] newArray(int size) { return new Currency[size]; }
    };
}
