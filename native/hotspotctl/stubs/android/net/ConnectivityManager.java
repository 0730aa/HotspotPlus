// COMPILE-ONLY STUB. Not shipped in the dex.
// Only exists so javac can subclass ConnectivityManager.OnStartTetheringCallback
// (an @hide abstract class). At runtime the REAL framework class is used.
package android.net;

public class ConnectivityManager {
    public static abstract class OnStartTetheringCallback {
        public void onTetheringStarted() {}
        public void onTetheringFailed() {}
    }
}
