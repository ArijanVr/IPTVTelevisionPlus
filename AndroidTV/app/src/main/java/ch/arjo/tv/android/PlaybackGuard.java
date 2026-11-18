package ch.arjo.tv.android;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Regeln für stabile Wiedergabe, gleich wie auf Samsung TV (SamsungTV/wgt/js/player.js). Ohne Android-Abhängigkeiten, damit
 * sie mit JUnit getestet werden kann; PlayerActivity führt die Entscheidungen aus.
 * <ul>
 * <li>Verbindungsfehler: höchstens 2 Wiederholungen nach 6 und 12 s; erst 30 s stabile Wiedergabe setzt den Zähler zurück.</li>
 * <li>Nach einem Verbindungsfehler mindestens 4 s zwischen Schliessen und Öffnen (Anbieter mit nur einer Verbindung).</li>
 * <li>Scheitert Live-TS vor dem ersten Bild an Format/Parser, einmal HLS (.m3u8) probieren und das Format merken.</li>
 * <li>Live puffert über 20 s: derselbe Sender wird neu geöffnet, höchstens 2-mal in 10 min.</li>
 * <li>Senderwechsel kurz hintereinander: erst nach 400 ms Ruhe öffnen.</li>
 * </ul>
 */
final class PlaybackGuard {
    static final long[] RETRY_WAIT_MS={6000,12000};
    static final long MIN_GAP_MS=4000, ZAP_GAP_MS=400, ZAP_WINDOW_MS=1500, STALL_MS=20000, STABLE_MS=30000, RECOVERY_WINDOW_MS=600000;
    static final int MAX_RECOVERIES=2;

    enum Kind { CONNECTION, UNAVAILABLE, FORMAT, BEHIND_LIVE }
    enum Action { RETRY, VARIANT, REPREPARE, GIVE_UP }
    static final class Decision {
        final Action action; final long delayMs; final Kind kind;
        Decision(Action action,long delayMs,Kind kind){this.action=action;this.delayMs=delayMs;this.kind=kind;}
    }

    /** Media3-Fehlercodes (PlaybackException.ERROR_CODE_*) in Klassen. */
    static Kind classify(int code){
        if(code==1002)return Kind.BEHIND_LIVE;                       // ERROR_CODE_BEHIND_LIVE_WINDOW
        if(code==2005||code==2007)return Kind.UNAVAILABLE;            // IO_FILE_NOT_FOUND, IO_CLEARTEXT_NOT_PERMITTED
        if(code==2004)return Kind.UNAVAILABLE;                        // IO_BAD_HTTP_STATUS (404/403 …)
        if(code>=3000&&code<5000)return Kind.FORMAT;                  // PARSING_*, DECODING_*, DECODER_*
        if(code>=6000&&code<7000)return Kind.FORMAT;                  // DRM
        return Kind.CONNECTION;                                       // IO_NETWORK_*, TIMEOUT, UNSPECIFIED, REMOTE …
    }

    private static final Pattern XTREAM_LIVE=Pattern.compile("^(https?://[^/]+)/(?:live/)?([^/]+)/([^/]+)/(\\d+)(?:\\.(ts|m3u8))?$");
    /** Live-Xtream-Adresse als TS und HLS; preferred "m3u8" stellt HLS nach vorn. Fremde Adressen bleiben unverändert. */
    static List<String> variants(String url,String preferred){
        Matcher m=XTREAM_LIVE.matcher(url==null?"":url);
        if(!m.matches())return new ArrayList<>(Arrays.asList(url));
        String b=m.group(1)+"/live/"+m.group(2)+"/"+m.group(3)+"/"+m.group(4);
        return "m3u8".equals(preferred)?new ArrayList<>(Arrays.asList(b+".m3u8",b+".ts")):new ArrayList<>(Arrays.asList(b+".ts",b+".m3u8"));
    }
    static String format(String url){return url==null?"":url.endsWith(".m3u8")?"m3u8":url.endsWith(".ts")?"ts":"";}

    private List<String> urls=new ArrayList<>();
    private int index,retry;
    private boolean started,live;
    private long lastClose=Long.MIN_VALUE/2,lastSelect=Long.MIN_VALUE/2,playingSince=-1,bufferingSince=-1,gap=ZAP_GAP_MS;
    private final List<Long> recoveries=new ArrayList<>();

    /** Neuer Sender/Film. Liefert die Wartezeit bis zum Öffnen (Zappen, Mindestabstand). */
    long select(String url,boolean live,String preferredFormat,long now){
        this.live=live;urls=live?variants(url,preferredFormat):new ArrayList<>(Arrays.asList(url));index=0;retry=0;started=false;recoveries.clear();
        playingSince=-1;bufferingSince=-1;
        boolean zapping=now-lastSelect<ZAP_WINDOW_MS;lastSelect=now;
        return Math.max(zapping?ZAP_GAP_MS:0,openDelay(now));
    }
    /** Wartezeit wegen Mindestabstand seit dem letzten Schliessen. */
    long openDelay(long now){return Math.max(0,lastClose+gap-now);}
    String url(){return urls.get(index);}
    void closed(long now){lastClose=now;}
    boolean hasStarted(){return started;}

    /** Erstes Bild bzw. wieder läuft. */
    void playing(long now){started=true;bufferingSince=-1;if(playingSince<0)playingSince=now;}
    void buffering(long now){if(bufferingSince<0)bufferingSince=now;playingSince=-1;}
    /** Regelmässig aufrufen: setzt den Zähler nach stabiler Wiedergabe zurück. */
    boolean stable(long now){if(retry>0&&playingSince>=0&&now-playingSince>=STABLE_MS){retry=0;return true;}return false;}

    Decision error(int code,long now){
        Kind kind=classify(code);
        if(kind==Kind.BEHIND_LIVE)return new Decision(Action.REPREPARE,0,kind);
        if(kind==Kind.CONNECTION)gap=MIN_GAP_MS;
        boolean tryOther=kind==Kind.FORMAT||kind==Kind.UNAVAILABLE;
        if(!started&&tryOther&&index+1<urls.size()){index++;retry=0;return new Decision(Action.VARIANT,0,kind);}
        if(kind==Kind.CONNECTION&&retry<RETRY_WAIT_MS.length){long w=RETRY_WAIT_MS[retry++];return new Decision(Action.RETRY,w,kind);}
        return new Decision(Action.GIVE_UP,0,kind);
    }
    /** Live puffert zu lange: true = neu öffnen, false = nichts tun; giveUp() danach prüfen. */
    boolean stalled(long now,boolean playWhenReady){
        if(!live||!playWhenReady||bufferingSince<0||now-bufferingSince<STALL_MS)return false;
        recoveries.removeIf(t->now-t>=RECOVERY_WINDOW_MS);
        if(recoveries.size()>=MAX_RECOVERIES)return false;
        recoveries.add(now);bufferingSince=-1;return true;
    }
    /** Grenze der Neustarts erreicht und es hängt weiter. */
    boolean stallGiveUp(long now,boolean playWhenReady){
        if(!live||!playWhenReady||bufferingSince<0||now-bufferingSince<STALL_MS)return false;
        recoveries.removeIf(t->now-t>=RECOVERY_WINDOW_MS);
        return recoveries.size()>=MAX_RECOVERIES;
    }
    int retries(){return retry;}
    int recoveryCount(){return recoveries.size();}
}
