package ch.arjo.tv.android;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import androidx.core.content.FileProvider;
import java.io.File;
import java.io.FileOutputStream;
import java.io.InputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.security.MessageDigest;
import org.json.JSONArray;
import org.json.JSONObject;

/** Selbst-Update: holt das neueste Release der öffentlichen Ablage, lädt die APK und startet den Android-Installer. */
final class Updater {
    static final String API = "https://api.github.com/repos/ArijanVr/IPTVTelevisionPlus/releases/latest";
    private static final String PREFS = "updater", LAST = "lastCheck";
    private static final long INTERVAL_MS = 24L * 3600 * 1000;

    static final class Info { String version, notes, apkUrl, sha256; }

    /** info == null und error == null: schon die neueste Version. */
    interface Result { void done(Info info, String error); }

    static boolean due(Context c) {
        return System.currentTimeMillis() - c.getSharedPreferences(PREFS, 0).getLong(LAST, 0) > INTERVAL_MS;
    }

    static void check(Context c, Result cb) {
        Context app = c.getApplicationContext();
        new Thread(() -> {
            Info info = null; String error = null;
            try {
                info = parse(new String(read(API), "UTF-8"), BuildConfig.VERSION_NAME);
                app.getSharedPreferences(PREFS, 0).edit().putLong(LAST, System.currentTimeMillis()).apply();
            } catch (Exception e) { error = String.valueOf(e.getMessage()); }
            Info finalInfo = info; String finalError = error;
            new Handler(Looper.getMainLooper()).post(() -> cb.done(finalInfo, finalError));
        }).start();
    }

    /** Liefert die Release-Daten, wenn sie neuer sind als {@code current} und eine Google-TV-APK enthalten; sonst null. */
    static Info parse(String json, String current) throws Exception {
        JSONObject release = new JSONObject(json);
        String tag = release.getString("tag_name");
        if (!isNewer(tag, current)) return null;
        JSONArray assets = release.optJSONArray("assets");
        for (int i = 0; assets != null && i < assets.length(); i++) {
            JSONObject a = assets.getJSONObject(i);
            String name = a.optString("name");
            if (name.endsWith(".apk") && name.contains("GoogleTV")) {
                Info info = new Info();
                info.version = tag.startsWith("v") ? tag.substring(1) : tag;
                info.notes = release.optString("body", "");
                info.apkUrl = a.getString("browser_download_url");
                String digest = a.optString("digest", "");
                info.sha256 = digest.startsWith("sha256:") ? digest.substring(7) : "";
                return info;
            }
        }
        throw new Exception("Release " + tag + " enthält keine Google-TV-APK.");
    }

    /** Zahlenweiser Vergleich wie «v1.10» gegen «1.9.9»; fehlende Stellen zählen als 0. */
    static boolean isNewer(String remote, String local) {
        int[] a = parts(remote), b = parts(local);
        for (int i = 0; i < Math.max(a.length, b.length); i++) {
            int x = i < a.length ? a[i] : 0, y = i < b.length ? b[i] : 0;
            if (x != y) return x > y;
        }
        return false;
    }

    private static int[] parts(String v) {
        if (v.startsWith("v") || v.startsWith("V")) v = v.substring(1);
        String[] p = v.split("\\.");
        int[] out = new int[p.length];
        for (int i = 0; i < p.length; i++) {
            String digits = p[i].replaceAll("^(\\d*).*$", "$1");
            out[i] = digits.isEmpty() ? 0 : Integer.parseInt(digits);
        }
        return out;
    }

    /** Lädt die APK in den Cache und startet den Installer; ohne Erlaubnis öffnet sich zuerst die Android-Einstellung. */
    static void install(Activity a, Info info, Result cb) {
        new Thread(() -> {
            String error = null; File apk = null;
            try {
                File dir = new File(a.getCacheDir(), "updates"); dir.mkdirs();
                apk = new File(dir, "IPTelevisionPlus-update.apk");
                MessageDigest md = MessageDigest.getInstance("SHA-256");
                try (InputStream in = open(info.apkUrl); FileOutputStream out = new FileOutputStream(apk)) {
                    byte[] buf = new byte[64 * 1024]; int n;
                    while ((n = in.read(buf)) > 0) { out.write(buf, 0, n); md.update(buf, 0, n); }
                }
                StringBuilder hex = new StringBuilder();
                for (byte b : md.digest()) hex.append(String.format("%02x", b));
                if (!info.sha256.isEmpty() && !info.sha256.equalsIgnoreCase(hex.toString())) {
                    apk.delete(); throw new Exception("Prüfsumme stimmt nicht, Update abgebrochen.");
                }
            } catch (Exception e) { error = String.valueOf(e.getMessage()); }
            File file = apk; String finalError = error;
            new Handler(Looper.getMainLooper()).post(() -> {
                if (finalError == null) launchInstaller(a, file);
                cb.done(null, finalError);
            });
        }).start();
    }

    private static void launchInstaller(Activity a, File apk) {
        if (!a.getPackageManager().canRequestPackageInstalls()) {
            a.startActivity(new Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:" + a.getPackageName())));
            return;
        }
        Uri uri = FileProvider.getUriForFile(a, a.getPackageName() + ".updates", apk);
        Intent intent = new Intent(Intent.ACTION_VIEW).setDataAndType(uri, "application/vnd.android.package-archive")
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION | Intent.FLAG_ACTIVITY_NEW_TASK);
        a.startActivity(intent);
    }

    private static InputStream open(String url) throws Exception {
        HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
        c.setConnectTimeout(15000); c.setReadTimeout(30000);
        c.setRequestProperty("Accept", "application/vnd.github+json");
        if (c.getResponseCode() != 200) throw new Exception("Server antwortet mit " + c.getResponseCode());
        return c.getInputStream();
    }

    private static byte[] read(String url) throws Exception {
        try (InputStream in = open(url)) {
            java.io.ByteArrayOutputStream out = new java.io.ByteArrayOutputStream();
            byte[] buf = new byte[8192]; int n;
            while ((n = in.read(buf)) > 0) out.write(buf, 0, n);
            return out.toByteArray();
        }
    }
}
