package ch.arjo.tv.android;

import android.content.Context;
import android.content.SharedPreferences;
import android.util.Log;
import org.json.JSONArray;

/** Lokale Wiedergabe-Diagnose: die letzten 200 Ereignisse (Puffer, Fehlercodes, Wiederholungen, Neustarts) in den App-Einstellungen
 *  «diag» und im Log (Tag IPTV). Nie Adressen, Zugangsdaten oder Pfade, nur Codes, Zähler und Formate. */
final class PlaybackDiag {
    private static final int MAX=200;
    private PlaybackDiag(){}
    static synchronized void log(Context c,String event,String detail){
        String line=System.currentTimeMillis()+" "+event+(detail==null||detail.isEmpty()?"":" "+detail);
        Log.i("IPTV",line);
        try{
            SharedPreferences p=c.getSharedPreferences("diag",0);JSONArray old=new JSONArray(p.getString("entries","[]")),next=new JSONArray();
            for(int i=Math.max(0,old.length()-(MAX-1));i<old.length();i++)next.put(old.getString(i));
            next.put(line);p.edit().putString("entries",next.toString()).apply();
        }catch(Exception ignored){}
    }
}
