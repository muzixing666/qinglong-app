package com.qinglong.mobile;

import android.content.Context;
import android.content.SharedPreferences;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import org.json.JSONObject;
import org.json.JSONArray;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;

/** All profiles, including application credentials, are encrypted by Android Keystore. */
final class ProfileStore {
    // All Activity instances share the same vault and Keystore alias. Never hold
    // this lock during a network call.
    static final Object TRANSACTION_LOCK = new Object();
    private static final String ALIAS = "qinglong.mobile.vault.v1";
    private final SharedPreferences prefs;
    ProfileStore(Context context) { prefs = context.getSharedPreferences("vault", Context.MODE_PRIVATE); }

    private SecretKey key() throws Exception {
        KeyStore ks = KeyStore.getInstance("AndroidKeyStore");
        ks.load(null);
        if (ks.containsAlias(ALIAS)) return ((KeyStore.SecretKeyEntry) ks.getEntry(ALIAS, null)).getSecretKey();
        KeyGenerator gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        gen.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return gen.generateKey();
    }

    JSONObject read() throws Exception {
        synchronized (TRANSACTION_LOCK) { return readLocked(); }
    }

    interface Mutation { void apply(JSONObject current) throws Exception; }

    /** Re-read, merge and persist under one process-wide lock. */
    JSONObject update(Mutation mutation) throws Exception {
        synchronized (TRANSACTION_LOCK) {
            JSONObject current = readLocked();
            mutation.apply(current);
            writeLocked(current);
            return current;
        }
    }

    private JSONObject readLocked() throws Exception {
        String saved = prefs.getString("profiles", null);
        if (saved == null) return new JSONObject().put("servers", new JSONArray()).put("activeId", "");
        String[] pieces = saved.split("\\.", 2);
        if (pieces.length != 2) throw new Exception("本地密钥库损坏，请在系统设置清除本 App 数据后重新添加面板。");
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(pieces[0], Base64.NO_WRAP)));
        return new JSONObject(new String(cipher.doFinal(Base64.decode(pieces[1], Base64.NO_WRAP)), StandardCharsets.UTF_8));
    }

    private void writeLocked(JSONObject value) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.ENCRYPT_MODE, key());
        String saved = Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP) + "." +
            Base64.encodeToString(cipher.doFinal(value.toString().getBytes(StandardCharsets.UTF_8)), Base64.NO_WRAP);
        if (!prefs.edit().putString("profiles", saved).commit()) throw new Exception("保存失败，请检查手机存储空间。");
    }
}
