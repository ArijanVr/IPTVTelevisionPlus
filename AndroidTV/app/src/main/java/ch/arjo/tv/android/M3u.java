package ch.arjo.tv.android;

import java.io.*;
import java.net.URI;
import java.util.*;
import java.util.regex.*;

public final class M3u {
    private static final Pattern ATTRIBUTE = Pattern.compile("([\\w-]+)\\s*=\\s*\"([^\"]*)\"");
    public static List<Entry> parse(Reader reader, String baseUrl) throws IOException {
        BufferedReader input = new BufferedReader(reader);
        List<Entry> result = new ArrayList<>();
        String line, name = "", group = "Ohne Gruppe", image = ""; boolean pending = false; int chno = 0;
        int count = 0;
        while ((line = input.readLine()) != null) {
            if (Thread.currentThread().isInterrupted()) throw new InterruptedIOException();
            if (++count > 1000000 || line.length() > 65536) throw new IOException("Playlist zu gross.");
            line = line.replace("\uFEFF", "").trim();
            if (line.startsWith("#EXTINF:")) {
                int comma = separator(line);
                name = comma >= 0 ? line.substring(comma + 1).trim() : "";
                group = "Ohne Gruppe"; image = ""; chno = 0;
                Matcher attributes = ATTRIBUTE.matcher(comma < 0 ? line : line.substring(0, comma));
                while (attributes.find()) {
                    if (attributes.group(1).equalsIgnoreCase("tvg-logo")) { try { image=URI.create(baseUrl).resolve(attributes.group(2)).toString(); } catch (Exception ignored) { image=""; } }
                    if (attributes.group(1).equalsIgnoreCase("group-title")) group = attributes.group(2);
                    if (attributes.group(1).equalsIgnoreCase("tvg-chno")) { try { chno = Math.max(0, Integer.parseInt(attributes.group(2).trim())); } catch (NumberFormatException ignored) { chno = 0; } }
                    if (name.isEmpty() && attributes.group(1).equalsIgnoreCase("tvg-name")) name = attributes.group(2);
                }
                pending = true;
            } else if (line.startsWith("#EXTGRP:") && pending) {
                group = line.substring(8).trim();
            } else if (!line.isEmpty() && !line.startsWith("#")) {
                String url;
                try { url = URI.create(baseUrl).resolve(line).toString(); } catch (Exception e) { pending = false; continue; }
                if (Source.isWeb(url)) {
                    String path = URI.create(url).getPath().toLowerCase(Locale.ROOT);
                    String kind = path.contains("/series/") || name.matches("(?i).*S\\d{1,2}E\\d{1,3}.*") ? "episode"
                        : path.contains("/movie/") || path.matches(".*\\.(mp4|mkv|avi|mov|m4v|webm)$") ? "movie" : "live";
                    result.add(new Entry(Source.hash(url), name.isEmpty() ? "Eintrag " + (result.size()+1) : name,
                        group.trim().isEmpty() ? "Ohne Gruppe" : group, url, kind, image, "").withSourceNumber(chno));
                }
                name = ""; group = "Ohne Gruppe"; image = ""; pending = false; chno = 0;
            }
        }
        return result;
    }
    static int separator(String line) {
        boolean quoted = false;
        for (int i = 0; i < line.length(); i++) {
            if (line.charAt(i) == '"') quoted = !quoted;
            if (line.charAt(i) == ',' && !quoted) return i;
        }
        return -1;
    }
}
