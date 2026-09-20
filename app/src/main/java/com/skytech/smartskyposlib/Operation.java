package com.skytech.smartskyposlib;
import android.os.Parcel;
import android.os.Parcelable;
import java.util.ArrayList;
public class Operation extends BaseBundleParcelable {
    public Operation() { super(); }
    protected Operation(Parcel in) { super(in, Operation.class.getClassLoader()); bundle.setClassLoader(Operation.class.getClassLoader()); }
    public String getName() { return bundle.getString("name"); }
    public String getType() { return bundle.getString("type"); }
    public String getTransactionType() { return bundle.getString("transactionType"); }
    public Boolean getEnableCpqr() { return get("enableCpqr"); }
    public Boolean getEnableMoto() { return get("enableMoto"); }
    public Boolean getEnableMotoCvv() { return get("enableMotoCvv"); }
    public Boolean getEnableMotoCvvSkip() { return get("enableMotoCvvSkip"); }
    public Boolean getEnableQr() { return get("enableQr"); }
    public Boolean getPasswordRequired() { return get("isPasswordRequired"); }
    @SuppressWarnings("unchecked") public ArrayList<Currency> getCurrencies() { return (ArrayList<Currency>) bundle.get("currencies"); }
    public static final Parcelable.Creator<Operation> CREATOR = new Parcelable.Creator<Operation>() {
        public Operation createFromParcel(Parcel in) { return new Operation(in); }
        public Operation[] newArray(int size) { return new Operation[size]; }
    };
}
