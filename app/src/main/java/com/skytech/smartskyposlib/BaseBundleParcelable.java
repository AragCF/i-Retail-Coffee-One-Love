package com.skytech.smartskyposlib;

import android.os.Bundle;
import android.os.Parcel;
import android.os.Parcelable;

abstract class BaseBundleParcelable implements Parcelable {
    protected final Bundle bundle;

    protected BaseBundleParcelable() {
        this.bundle = new Bundle();
    }

    protected BaseBundleParcelable(Parcel in, ClassLoader loader) {
        Bundle value = in.readBundle(loader);
        this.bundle = value != null ? value : new Bundle();
    }

    @Override
    public int describeContents() { return 0; }

    @Override
    public void writeToParcel(Parcel dest, int flags) {
        dest.writeBundle(bundle);
    }

    public Bundle getBundleCopy() {
        return new Bundle(bundle);
    }

    @SuppressWarnings("unchecked")
    protected <T> T get(String key) {
        return (T) bundle.get(key);
    }
}
