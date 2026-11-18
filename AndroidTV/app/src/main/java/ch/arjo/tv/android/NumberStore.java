package ch.arjo.tv.android;

import android.content.SharedPreferences;
import java.util.*;
import org.json.*;

/** Speichert die festen Kanalnummern je Quelle (Kanal-ID → Nummer) und setzt sie auf Live-Einträge. */
final class NumberStore {
    private NumberStore(){}
    private static String key(String scope){return "numbers:"+scope;}
    static Map<String,Integer> load(SharedPreferences prefs,String scope){
        Map<String,Integer> out=new HashMap<>();
        try{JSONObject o=new JSONObject(prefs.getString(key(scope),"{}"));Iterator<String> it=o.keys();while(it.hasNext()){String id=it.next();int n=o.optInt(id,0);if(n>=1)out.put(id,n);}}catch(JSONException ignored){}
        return out;
    }
    /** Vergibt Nummern für alle Live-Einträge (bisherige bleiben) und speichert sie. */
    static void apply(SharedPreferences prefs,String scope,List<Entry> entries,boolean persist){
        List<String> ids=new ArrayList<>();List<Integer> source=new ArrayList<>();List<Entry> live=new ArrayList<>();
        for(Entry e:entries)if(e.kind.equals("live")){ids.add(e.id);source.add(e.sourceNumber);live.add(e);}
        ChannelNumbers.Result r=ChannelNumbers.assign(ids,source,load(prefs,scope),pinned(prefs,scope));
        for(Entry e:live){Integer n=r.numbers.get(e.id);e.number=n==null?0:n;}
        if(persist){JSONObject o=new JSONObject();try{for(Map.Entry<String,Integer> m:r.numbers.entrySet())o.put(m.getKey(),m.getValue());}catch(JSONException ignored){}prefs.edit().putString(key(scope),o.toString()).apply();}
    }
    static Map<String,Integer> pinned(SharedPreferences prefs,String scope){
        Map<String,Integer> out=new HashMap<>();
        try{JSONObject o=new JSONObject(prefs.getString("pinned:"+scope,"{}"));Iterator<String> it=o.keys();while(it.hasNext()){String id=it.next();int n=o.optInt(id,0);if(n>=1)out.put(id,n);}}catch(JSONException ignored){}
        return out;
    }
}
