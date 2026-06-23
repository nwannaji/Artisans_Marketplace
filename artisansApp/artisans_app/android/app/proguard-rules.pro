####################################
# General Keep Rules
####################################
-keepattributes *Annotation*
-keep class androidx.annotation.Keep

-keepclassmembers class * {
    public <init>(...);
}

-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

####################################
# Google Maps / Play Services
####################################
-keep class com.google.android.gms.maps.** { *; }
-keep class com.google.android.gms.internal.** { *; }
-keep class com.google.maps.android.** { *; }
-keep class android.support.v4.** { *; }

# Keep Parcelable CREATOR fields — prevents NoSuchFieldError crashes
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Keep all serializable classes used by Maps SDK
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Keep Google Play Services client classes
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.dynamite.** { *; }
-keep class com.google.android.gms.flags.** { *; }