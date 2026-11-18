package ch.arjo.tv.android;

import java.net.URI;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import org.json.JSONObject;

public final class Source {
    public final String mode, address, user, password;
    public Source(String mode, String address, String user, String password) {
        this.mode = mode; this.address = address.trim(); this.user = user.trim(); this.password = password;
        URI uri = URI.create(this.address);
        if (!isWeb(this.address) || uri.getUserInfo() != null || uri.getFragment() != null)
            throw new IllegalArgumentException("Bitte eine gültige HTTP-/HTTPS-Adresse eingeben.");
        if (mode.equals("xtream") && (this.user.isEmpty() || password.isEmpty()))
            throw new IllegalArgumentException("Benutzername und Passwort fehlen.");
    }
    public static boolean isWeb(String value) {
        try { URI u = URI.create(value); return ("https".equalsIgnoreCase(u.getScheme()) || "http".equalsIgnoreCase(u.getScheme())) && u.getHost() != null; }
        catch (Exception e) { return false; }
    }
    public static String encode(String value) { try { return URLEncoder.encode(value, "UTF-8").replace("+", "%20"); } catch (java.io.UnsupportedEncodingException e) { throw new AssertionError(e); } }
    public String base() {
        URI u = URI.create(address);
        return u.getScheme() + "://" + u.getRawAuthority();
    }
    public String api(String action) {
        return base() + "/player_api.php?username=" + encode(user) + "&password=" + encode(password)
            + (action.isEmpty() ? "" : "&action=" + encode(action));
    }
    public String stream(String kind, String id, String extension) {
        if (!id.matches("[0-9]+") || !extension.matches("[A-Za-z0-9]+")) throw new IllegalArgumentException("Ungültiger Stream.");
        return base() + "/" + kind + "/" + encode(user) + "/" + encode(password) + "/" + id + "." + extension;
    }
    public String scope() { return hash(mode + "|" + (mode.equals("xtream") ? base() + "|" + user : address)); }
    public static String hash(String value) {
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(value.getBytes(StandardCharsets.UTF_8));
            char[] hex="0123456789abcdef".toCharArray(), out=new char[digest.length*2];
            for(int i=0;i<digest.length;i++){out[i*2]=hex[(digest[i]&255)>>>4];out[i*2+1]=hex[digest[i]&15];}return new String(out);
        } catch (Exception e) { throw new IllegalStateException("Kennung konnte nicht erstellt werden."); }
    }
    JSONObject json() throws Exception { return new JSONObject().put("mode", mode).put("address", address).put("user", user).put("password", password); }
    static Source from(JSONObject j) { return new Source(j.optString("mode"), j.optString("address"), j.optString("user"), j.optString("password")); }
}
