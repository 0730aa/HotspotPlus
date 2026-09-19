// COMPILE-ONLY STUB. Not shipped in the dex.
// 让 javac 能子类化 IIntResultListener.Stub（AIDL 回调，@hide）。
// 运行时解析到真实的 framework 类（Stub extends Binder implements IIntResultListener）。
package android.net;

public interface IIntResultListener {
    void onResult(int resultCode);

    class Stub implements IIntResultListener {
        public void onResult(int resultCode) {}
    }
}
