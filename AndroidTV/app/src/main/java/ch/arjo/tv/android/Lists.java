package ch.arjo.tv.android;

import android.content.SharedPreferences;
import org.json.*;
import java.util.*;

/** Meine Listen: ausgeblendete Sender und Kategorien, eigene Reihenfolge und Namen, Aufbau der Startseite und Kacheldarstellung. */
final class Lists {
    static final String[] SECTIONS={"hero","continue","last","favorites","live","movies","series"};
    static final String[] SECTION_LABELS={"Titelbild","Weiterschauen","Zuletzt gesehen","Favoriten","Live TV","Neue Filme","Neue Serien"};
    static final String[] AREAS={"live","movie","series"}, AREA_LABELS={"Live","Filme","Serien"};
    static final String[] SIZES={"Kompakt","Normal","Gross"};
    private final SharedPreferences prefs;
    private final String scope;
    Lists(SharedPreferences prefs,String scope){this.prefs=prefs;this.scope=scope;}
    private String key(String name){return "lists:"+scope+":"+name;}
    static String area(Entry e){return e.kind.equals("episode")?"series":e.kind;}
    static String sectionLabel(String section){int i=Arrays.asList(SECTIONS).indexOf(section);return i<0?section:SECTION_LABELS[i];}
    static String areaLabel(String area){int i=Arrays.asList(AREAS).indexOf(area);return i<0?area:AREA_LABELS[i];}

    // Sichtbarkeit
    private Set<String> set(String name){return new HashSet<>(prefs.getStringSet(key(name),Collections.emptySet()));}
    private void toggle(String name,String value,boolean on){Set<String> s=set(name);if(on)s.add(value);else s.remove(value);prefs.edit().putStringSet(key(name),s).apply();}
    boolean hidden(Entry e){return set("hidden").contains(e.id)||groupHidden(area(e),e.group);}
    boolean channelHidden(Entry e){return set("hidden").contains(e.id);}
    void setHidden(Entry e,boolean hidden){toggle("hidden",e.id,hidden);}
    boolean groupHidden(String area,String group){return set("hiddenGroups").contains(area+"\n"+group);}
    void setGroupHidden(String area,String group,boolean hidden){toggle("hiddenGroups",area+"\n"+group,hidden);}
    List<Entry> visible(List<Entry> all){List<Entry> out=new ArrayList<>();Set<String> ids=set("hidden"),groups=set("hiddenGroups");for(Entry e:all)if(!ids.contains(e.id)&&!groups.contains(area(e)+"\n"+e.group))out.add(e);return out;}

    // Eigene Namen (leer = Originalname)
    private JSONObject map(String name){try{return new JSONObject(prefs.getString(key(name),"{}"));}catch(JSONException e){return new JSONObject();}}
    private void put(String name,String k,String value){JSONObject m=map(name);try{if(value==null||value.trim().isEmpty())m.remove(k);else m.put(k,value.trim());}catch(JSONException ignored){}prefs.edit().putString(key(name),m.toString()).apply();}
    String name(Entry e){String custom=map("names").optString(e.id,"");return custom.isEmpty()?e.name:custom;}
    void rename(Entry e,String name){put("names",e.id,name);}
    String groupName(String area,String group){String custom=map("groupNames").optString(area+"\n"+group,"");return custom.isEmpty()?group:custom;}
    void renameGroup(String area,String group,String name){put("groupNames",area+"\n"+group,name);}

    // Reihenfolge der Kategorien: eigene Positionen zuerst, unbekannte Gruppen folgen in der Reihenfolge des Anbieters.
    private List<String> list(String name){List<String> out=new ArrayList<>();try{JSONArray a=new JSONArray(prefs.getString(key(name),"[]"));for(int i=0;i<a.length();i++)out.add(a.getString(i));}catch(JSONException ignored){}return out;}
    private void list(String name,List<String> values){prefs.edit().putString(key(name),new JSONArray(values).toString()).apply();}
    List<String> ordered(String area,Collection<String> groups){
        List<String> order=list("order:"+area),out=new ArrayList<>();Set<String> present=new LinkedHashSet<>(groups);
        for(String g:order)if(present.remove(g))out.add(g);out.addAll(present);return out;
    }
    void move(String area,Collection<String> groups,String group,int offset){
        List<String> order=ordered(area,groups);int i=order.indexOf(group),j=i+offset;if(i<0||j<0||j>=order.size())return;
        order.add(j,order.remove(i));list("order:"+area,order);
    }
    boolean customOrder(String area){return !list("order:"+area).isEmpty();}
    void resetOrder(String area){prefs.edit().remove(key("order:"+area)).apply();}

    // Startseite
    List<String> homeOrder(){return ordered("home",Arrays.asList(SECTIONS));}
    boolean sectionHidden(String section){return set("hiddenSections").contains(section);}
    void setSectionHidden(String section,boolean hidden){toggle("hiddenSections",section,hidden);}
    void moveSection(String section,int offset){move("home",Arrays.asList(SECTIONS),section,offset);}
    List<String> visibleSections(){List<String> out=new ArrayList<>();for(String s:homeOrder())if(!sectionHidden(s))out.add(s);return out;}
    void resetHome(){prefs.edit().remove(key("order:home")).remove(key("hiddenSections")).apply();}

    // Kacheln (gelten für alle Quellen)
    boolean showNames(){return prefs.getBoolean("tiles:names",true);}
    void setShowNames(boolean show){prefs.edit().putBoolean("tiles:names",show).apply();}
    int tileSize(){return Math.max(0,Math.min(2,prefs.getInt("tiles:size",1)));}
    void setTileSize(int size){prefs.edit().putInt("tiles:size",Math.max(0,Math.min(2,size))).apply();}
    /** Breite einer Senderkachel in dp (16:9-Logofläche). */
    int tileWidth(){return new int[]{150,188,236}[tileSize()];}
}
