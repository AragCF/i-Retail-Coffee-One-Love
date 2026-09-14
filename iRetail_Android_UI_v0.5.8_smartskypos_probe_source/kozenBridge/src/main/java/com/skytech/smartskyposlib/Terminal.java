package com.skytech.smartskyposlib;

import android.os.Parcel;
import android.os.Parcelable;
import java.util.ArrayList;

public class Terminal extends BaseBundleParcelable {
    public Terminal() { super(); }
    protected Terminal(Parcel in) {
        super(in, Terminal.class.getClassLoader());
        bundle.setClassLoader(Terminal.class.getClassLoader());
    }

    public String getTerminalId() { return bundle.getString("terminalId"); }
    public String getTerminalName() { return bundle.getString("terminalName"); }
    @SuppressWarnings("unchecked") public ArrayList<Operation> getOperations() { return (ArrayList<Operation>) bundle.get("operations"); }

    public static final Parcelable.Creator<Terminal> CREATOR = new Parcelable.Creator<Terminal>() {
        @Override public Terminal createFromParcel(Parcel in) { return new Terminal(in); }
        @Override public Terminal[] newArray(int size) { return new Terminal[size]; }
    };
}
