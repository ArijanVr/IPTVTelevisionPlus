package ch.arjo.tv.android;

import android.content.Context;
import android.security.keystore.KeyGenParameterSpec;
import android.security.keystore.KeyProperties;
import android.util.Base64;
import javax.crypto.*;
import javax.crypto.spec.GCMParameterSpec;
import java.nio.charset.StandardCharsets;
import java.security.KeyStore;
import org.json.JSONObject;

/** Only encrypted source data leaves memory. Backup is disabled in the manifest. */
final class Vault {
    private static final String ALIAS = "arjotv.android.source.v1";
    private final Context context;
    Vault(Context context) { this.context = context; }
    private SecretKey key() throws Exception {
        KeyStore store = KeyStore.getInstance("AndroidKeyStore"); store.load(null);
        if (store.containsAlias(ALIAS)) return (SecretKey)store.getKey(ALIAS, null);
        KeyGenerator generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore");
        generator.init(new KeyGenParameterSpec.Builder(ALIAS, KeyProperties.PURPOSE_ENCRYPT | KeyProperties.PURPOSE_DECRYPT)
            .setBlockModes(KeyProperties.BLOCK_MODE_GCM).setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build());
        return generator.generateKey();
    }
    void save(Source source) throws Exception { write("",source.json()); }
    private void write(String prefix, JSONObject value) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding"); cipher.init(Cipher.ENCRYPT_MODE, key());
        byte[] encrypted = cipher.doFinal(value.toString().getBytes(StandardCharsets.UTF_8));
        boolean saved = context.getSharedPreferences("vault", 0).edit()
            .putString(prefix+"iv", Base64.encodeToString(cipher.getIV(), Base64.NO_WRAP))
            .putString(prefix+"data", Base64.encodeToString(encrypted, Base64.NO_WRAP)).commit();
        if (!saved) throw new Exception("Speichern fehlgeschlagen.");
    }
    Source load() throws Exception { JSONObject value=read(""); return value==null ? null : Source.from(value); }
    private JSONObject read(String prefix) throws Exception {
        String encrypted = context.getSharedPreferences("vault", 0).getString(prefix+"data", null);
        if (encrypted == null) return null;
        String iv = context.getSharedPreferences("vault", 0).getString(prefix+"iv", "");
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(Cipher.DECRYPT_MODE, key(), new GCMParameterSpec(128, Base64.decode(iv, Base64.NO_WRAP)));
        return new JSONObject(new String(cipher.doFinal(Base64.decode(encrypted, Base64.NO_WRAP)), StandardCharsets.UTF_8));
    }
    void saveHistory(String scope, java.util.List<Entry> entries) throws Exception {
        org.json.JSONArray list=new org.json.JSONArray(); for(Entry e:entries)list.put(e.json()); write("history:"+scope,new JSONObject().put("entries",list));
    }
    java.util.List<Entry> history(String scope) throws Exception {
        java.util.List<Entry> entries=new java.util.ArrayList<>();JSONObject value=read("history:"+scope);if(value==null)return entries;
        org.json.JSONArray list=value.optJSONArray("entries");if(list!=null)for(int i=0;i<Math.min(30,list.length());i++)if(list.optJSONObject(i)!=null)entries.add(Entry.from(list.optJSONObject(i)));return entries;
    }
    /** Zufälliger Schlüssel für den Katalog-Zwischenspeicher. Er liegt verschlüsselt im Vault und geht mit forget() verloren. */
    byte[] cacheKey() throws Exception {
        JSONObject value=read("cache:");
        if(value==null){byte[] fresh=new byte[32];new java.security.SecureRandom().nextBytes(fresh);write("cache:",new JSONObject().put("k",Base64.encodeToString(fresh,Base64.NO_WRAP)));return fresh;}
        return Base64.decode(value.getString("k"),Base64.NO_WRAP);
    }
    void forget() { context.getSharedPreferences("vault", 0).edit().clear().apply(); }
}
