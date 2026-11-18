package ch.arjo.tv.android;

import android.content.Context;
import android.util.JsonReader;
import android.util.JsonToken;
import android.util.JsonWriter;
import java.io.*;
import java.nio.charset.StandardCharsets;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.List;
import java.util.zip.GZIPInputStream;
import java.util.zip.GZIPOutputStream;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/**
 * Lokaler Zwischenspeicher für geparste Kataloge, damit die App nach dem Beenden nicht jedes Mal die ganze Liste neu lädt.
 * Die Stream-Adressen können Zugangsdaten enthalten: Die Dateien sind komprimiert und mit AES-GCM verschlüsselt. Der Schlüssel
 * liegt im Vault (Android Keystore). Liegen sie im Cache-Ordner, kann Android sie jederzeit entfernen; dann wird neu geladen.
 */
final class CatalogCache {
    /** Ab diesem Alter wird im Hintergrund aktualisiert; bis dahin zeigt die App den gespeicherten Stand. */
    static final long MAX_AGE_MS = 6L * 60 * 60 * 1000;
    private static final int VERSION = 1;
    private final File dir;
    private final KeySource keys;

    interface KeySource { byte[] get() throws Exception; }

    static final class Hit {
        final List<Entry> entries; final long savedAt;
        Hit(List<Entry> entries, long savedAt) { this.entries = entries; this.savedAt = savedAt; }
        boolean stale() { return System.currentTimeMillis() - savedAt > MAX_AGE_MS; }
    }

    CatalogCache(Context context, KeySource keys) { this.dir = new File(context.getCacheDir(), "catalog"); this.keys = keys; }

    private File file(String scope, String key) { return new File(dir, Source.hash(scope + "|" + key) + ".bin"); }

    /**
     * Schreibt zuerst in eine Zwischendatei und benennt sie danach um. Fehler sind nicht schlimm: dann wird beim nächsten Start neu geladen.
     * Es wird gestreamt: JSON, dann gzip, dann in Blöcken zu 64 KB verschlüsselt. So braucht das Speichern kaum Arbeitsspeicher
     * (der Heap auf dem Fernseher ist mit rund 130 000 Einträgen schon fast voll) und bleibt schnell, weil GCM nie in winzigen Teilen läuft.
     */
    void save(String scope, String key, List<Entry> entries) {
        File target = file(scope, key), temp = new File(dir, target.getName() + ".tmp");
        try {
            if (!dir.isDirectory() && !dir.mkdirs()) return;
            byte[] secret = keys.get();
            try (JsonWriter out = new JsonWriter(new BufferedWriter(new OutputStreamWriter(new FastGzip(new Sealer(new FileOutputStream(temp), secret)), StandardCharsets.UTF_8), 1 << 16))) {
                out.beginObject().name("v").value(VERSION).name("t").value(System.currentTimeMillis()).name("entries").beginArray();
                for (Entry e : entries) {
                    out.beginObject().name("id").value(e.id).name("name").value(e.name).name("group").value(e.group).name("url").value(e.url)
                        .name("kind").value(e.kind).name("image").value(e.image).name("subtitle").value(e.subtitle)
                        .name("number").value(e.number).name("sourceNumber").value(e.sourceNumber).endObject();
                }
                out.endArray().endObject();
            }
            if (!temp.renameTo(target)) { temp.delete(); }
        } catch (Throwable e) { temp.delete(); target.delete(); }
    }

    private static final int CHUNK = 1 << 16;

    private static final class FastGzip extends GZIPOutputStream {
        FastGzip(OutputStream out) throws IOException { super(out, 1 << 14); def.setLevel(java.util.zip.Deflater.BEST_SPEED); }
    }

    private static Cipher cipher(int mode, byte[] secret, byte[] iv) throws Exception {
        Cipher cipher = Cipher.getInstance("AES/GCM/NoPadding");
        cipher.init(mode, new SecretKeySpec(secret, "AES"), new GCMParameterSpec(128, iv));
        return cipher;
    }

    /** Verschlüsselt in Blöcken: je Block Länge (4 Byte), IV (12 Byte), Chiffre mit Tag. */
    private static final class Sealer extends OutputStream {
        private final DataOutputStream out; private final byte[] secret; private final byte[] buffer = new byte[CHUNK]; private int size; private final SecureRandom random = new SecureRandom();
        Sealer(OutputStream out, byte[] secret) { this.out = new DataOutputStream(new BufferedOutputStream(out, 1 << 16)); this.secret = secret; }
        @Override public void write(int b) throws IOException { write(new byte[]{(byte) b}, 0, 1); }
        @Override public void write(byte[] data, int offset, int length) throws IOException {
            while (length > 0) {
                int n = Math.min(length, CHUNK - size);
                System.arraycopy(data, offset, buffer, size, n); size += n; offset += n; length -= n;
                if (size == CHUNK) seal();
            }
        }
        private void seal() throws IOException {
            if (size == 0) return;
            try {
                byte[] iv = new byte[12]; random.nextBytes(iv);
                byte[] sealed = cipher(Cipher.ENCRYPT_MODE, secret, iv).doFinal(buffer, 0, size);
                out.writeInt(sealed.length); out.write(iv); out.write(sealed); size = 0;
            } catch (IOException e) { throw e; } catch (Exception e) { throw new IOException(e); }
        }
        @Override public void close() throws IOException { try { seal(); out.flush(); } finally { out.close(); } }
    }

    private static final class Opener extends InputStream {
        private final DataInputStream in; private final byte[] secret; private byte[] block = new byte[0]; private int position;
        Opener(InputStream in, byte[] secret) { this.in = new DataInputStream(new BufferedInputStream(in, 1 << 16)); this.secret = secret; }
        private boolean next() throws IOException {
            int length;
            try { length = in.readInt(); } catch (EOFException e) { return false; }
            if (length < 16 || length > CHUNK + 16) throw new IOException("Ungültiger Block.");
            byte[] iv = new byte[12]; in.readFully(iv); byte[] sealed = new byte[length]; in.readFully(sealed);
            try { block = cipher(Cipher.DECRYPT_MODE, secret, iv).doFinal(sealed); position = 0; return true; }
            catch (IOException e) { throw e; } catch (Exception e) { throw new IOException(e); }
        }
        @Override public int read() throws IOException { byte[] one = new byte[1]; return read(one, 0, 1) < 0 ? -1 : one[0] & 255; }
        @Override public int read(byte[] data, int offset, int length) throws IOException {
            while (position >= block.length) if (!next()) return -1;
            int n = Math.min(length, block.length - position);
            System.arraycopy(block, position, data, offset, n); position += n; return n;
        }
        @Override public void close() throws IOException { in.close(); }
    }

    /** Gespeicherter Katalogteil oder null (nichts gespeichert, beschädigt, anderer Schlüssel, falsche Version). */
    Hit load(String scope, String key) {
        File source = file(scope, key);
        if (!source.isFile()) return null;
        try (JsonReader in = new JsonReader(new BufferedReader(new InputStreamReader(new GZIPInputStream(new Opener(new FileInputStream(source), keys.get()), 1 << 14), StandardCharsets.UTF_8), 1 << 16))) {
            int version = 0; long savedAt = 0; List<Entry> entries = null;
            in.beginObject();
            while (in.hasNext()) {
                String name = in.nextName();
                if (name.equals("v")) version = in.nextInt();
                else if (name.equals("t")) savedAt = in.nextLong();
                else if (name.equals("entries")) {
                    entries = new ArrayList<>(); in.beginArray();
                    while (in.hasNext()) entries.add(entry(in));
                    in.endArray();
                } else in.skipValue();
            }
            in.endObject();
            if (version != VERSION || entries == null || entries.isEmpty()) throw new IOException();
            return new Hit(entries, savedAt);
        } catch (Throwable e) { source.delete(); return null; }
    }

    private static Entry entry(JsonReader in) throws IOException {
        String id = "", name = "", group = "", url = "", kind = "", image = "", subtitle = ""; int number = 0, sourceNumber = 0;
        in.beginObject();
        while (in.hasNext()) {
            String field = in.nextName();
            if (in.peek() == JsonToken.NULL) { in.skipValue(); continue; }
            switch (field) {
                case "id": id = in.nextString(); break; case "name": name = in.nextString(); break; case "group": group = in.nextString(); break;
                case "url": url = in.nextString(); break; case "kind": kind = in.nextString(); break; case "image": image = in.nextString(); break;
                case "subtitle": subtitle = in.nextString(); break; case "number": number = in.nextInt(); break; case "sourceNumber": sourceNumber = in.nextInt(); break;
                default: in.skipValue();
            }
        }
        in.endObject();
        return new Entry(id, name, group, url, kind, image, subtitle).withNumber(number).withSourceNumber(sourceNumber);
    }

    void clear() {
        File[] files = dir.listFiles();
        if (files != null) for (File f : files) f.delete();
    }
}
