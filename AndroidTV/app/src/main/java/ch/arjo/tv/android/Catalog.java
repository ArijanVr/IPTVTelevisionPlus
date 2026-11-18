package ch.arjo.tv.android;

import org.json.*;
import java.io.*;
import java.net.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.zip.GZIPInputStream;

public final class Catalog {
    private final Source source;
    public Catalog(Source source) { this.source = source; }
    private interface Read<T> { T read(Reader r) throws Exception; }
    private <T> T request(String url, Read<T> read) throws Exception {
        if (!Source.isWeb(url)) throw new IOException();
        HttpURLConnection connection = (HttpURLConnection) URI.create(url).toURL().openConnection();
        connection.setConnectTimeout(15000); connection.setReadTimeout(30000);
        connection.setRequestProperty("User-Agent", "ARJOTV-Android/0.1");
        connection.setRequestProperty("Accept-Encoding", "gzip");
        try {
            int code = connection.getResponseCode();
            if (code == 401 || code == 403) throw new IOException("Anmeldung abgelehnt. Bitte Zugang prüfen.");
            if (code < 200 || code > 299) throw new IOException("Server antwortet nicht erfolgreich (" + code + ").");
            InputStream body = connection.getInputStream();
            if ("gzip".equalsIgnoreCase(connection.getContentEncoding())) body = new GZIPInputStream(body);
            try (Reader reader = new InputStreamReader(body, StandardCharsets.UTF_8)) { return read.read(reader); }
        } finally { connection.disconnect(); }
    }
    private Object json(String url) throws Exception {
        return request(url, reader -> {
            StringBuilder body = new StringBuilder(); char[] buffer = new char[8192]; int n;
            while ((n = reader.read(buffer)) != -1) {
                if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException();
                if (body.length() + n > 48 * 1024 * 1024) throw new IOException("Serverantwort zu gross.");
                body.append(buffer, 0, n);
            }
            return new JSONTokener(body.toString()).nextValue();
        });
    }
    /** Prüft den Zugang. Liefert das Ablaufdatum des Abos (Sekunden seit 1970) oder 0, wenn unbekannt oder unbegrenzt. */
    public long authenticate() throws Exception {
        if (!source.mode.equals("xtream")) return 0;
        Object response = json(source.api(""));
        if (!(response instanceof JSONObject)) throw new IOException("Ungültige Serverantwort.");
        JSONObject info = ((JSONObject)response).optJSONObject("user_info");
        if (info == null || !(info.optString("auth").equals("1") || info.optString("auth").equals("true")))
            throw new IOException("Anmeldung abgelehnt. Bitte Zugang prüfen.");
        if (!info.optString("status", "Active").equalsIgnoreCase("Active")) throw new IOException("Dein Zugang ist nicht aktiv.");
        long expiry = info.optLong("exp_date", 0);
        if (expiry > 0 && expiry * 1000 <= System.currentTimeMillis()) throw new IOException("Dein Abo ist abgelaufen.");
        return Math.max(expiry, 0);
    }
    private JSONArray array(String action) throws Exception {
        Object response = json(source.api(action));
        if (!(response instanceof JSONArray)) throw new IOException("Der Anbieter liefert keine gültige Liste.");
        return (JSONArray)response;
    }
    public List<Entry> load(String kind) throws Exception {
        if (!source.mode.equals("xtream")) return request(source.address, r -> M3u.parse(r, source.address));
        String prefix = kind.equals("live") ? "live" : kind.equals("movie") ? "vod" : "series";
        JSONArray categories = array("get_" + prefix + "_categories");
        Map<String,String> groups = new LinkedHashMap<>();
        for (int i=0; i<categories.length(); i++) {
            JSONObject c = categories.optJSONObject(i); if (c != null) groups.put(c.optString("category_id"), c.optString("category_name", "Ohne Gruppe"));
        }
        JSONArray rows = array(kind.equals("series") ? "get_series" : "get_" + prefix + "_streams");
        List<Entry> entries = new ArrayList<>();
        for (int i=0; i<rows.length(); i++) {
            JSONObject j = rows.optJSONObject(i); if (j == null) continue;
            String id = j.optString(kind.equals("series") ? "series_id" : "stream_id");
            if (!id.matches("[0-9]+")) continue;
            String ext = j.optString("container_extension", kind.equals("live") ? "ts" : "mp4");
            if (!ext.matches("[A-Za-z0-9]+")) ext = "mp4";
            entries.add(new Entry(kind + ":" + id, j.optString("name", "Eintrag " + id), groups.getOrDefault(j.optString("category_id"), "Ohne Gruppe"),
                kind.equals("series") ? "" : source.stream(kind.equals("movie") ? "movie" : "live", id, ext), kind, j.optString(kind.equals("series") ? "cover" : "stream_icon"), metadata(j)).withSourceNumber(kind.equals("live") ? Math.max(0, j.optInt("num", 0)) : 0));
        }
        return entries;
    }
    public List<Entry> episodes(Entry series) throws Exception {
        Object response = json(source.api("get_series_info") + "&series_id=" + Source.encode(series.id.substring(series.id.indexOf(':')+1)));
        if (!(response instanceof JSONObject)) throw new IOException();
        return episodes((JSONObject)response);
    }
    public List<Entry> episodes(JSONObject response) throws Exception {
        JSONObject seasons = response.optJSONObject("episodes");
        if (seasons == null) throw new IOException("Keine Episoden verfügbar.");
        List<Entry> result = new ArrayList<>();
        List<String> keys = new ArrayList<>(); seasons.keys().forEachRemaining(keys::add);
        keys.sort(Comparator.comparingInt(Catalog::number));
        for (String season : keys) {
            JSONArray episodes = seasons.optJSONArray(season); if (episodes == null) continue;
            List<JSONObject> sorted = new ArrayList<>();
            for (int i=0; i<episodes.length(); i++) if (episodes.optJSONObject(i) != null) sorted.add(episodes.optJSONObject(i));
            sorted.sort(Comparator.comparingInt(j -> j.optInt("episode_num", 0)));
            for (JSONObject e : sorted) {
                String id = e.optString("id"), ext = e.optString("container_extension", "mp4");
                if (!id.matches("[0-9]+")) continue;
                if (!ext.matches("[A-Za-z0-9]+")) ext = "mp4";
                result.add(new Entry("episode:" + id, e.optString("title", "Episode " + e.optInt("episode_num")), "Staffel " + season,
                    source.stream("series", id, ext), "episode", e.optJSONObject("info")==null ? "" : e.optJSONObject("info").optString("movie_image"), "Episode " + e.optInt("episode_num")));
            }
        }
        return result;
    }
    private static String metadata(JSONObject item) {
        List<String> parts=new ArrayList<>();
        String year=item.optString("year"); if (year.isEmpty()) { String date=item.optString("releaseDate"); if (date.length()>=4) year=date.substring(0,4); }
        if (!year.isEmpty() && !year.equals("null")) parts.add(year);
        String rating=item.optString("rating"); if (!rating.isEmpty() && !rating.equals("0") && !rating.equals("null")) parts.add("★ " + rating);
        return String.join(" · ",parts);
    }
    public JSONObject detail(Entry entry) throws Exception {
        String id=entry.id.substring(entry.id.indexOf(':')+1);
        Object response=json(source.api(entry.kind.equals("series") ? "get_series_info" : "get_vod_info") + (entry.kind.equals("series") ? "&series_id=" : "&vod_id=") + Source.encode(id));
        if (!(response instanceof JSONObject)) throw new IOException();
        return (JSONObject)response;
    }
    static int number(String value) { try { return Integer.parseInt(value); } catch (Exception e) { return Integer.MAX_VALUE; } }
}
