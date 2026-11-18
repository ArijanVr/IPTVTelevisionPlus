package ch.arjo.tv.android;

import org.json.JSONObject;

public final class Entry {
    public final String id, name, group, url, kind, image, subtitle;
    /** Feste Kanalnummer (0 = noch keine) und Nummer aus der Quelle (tvg-chno bzw. num, 0 = keine). */
    public int number, sourceNumber;
    public Entry(String id, String name, String group, String url, String kind) { this(id,name,group,url,kind,"",""); }
    public Entry(String id, String name, String group, String url, String kind, String image, String subtitle) {
        this.id=id; this.name=name; this.group=group; this.url=url; this.kind=kind;
        this.image=Source.isWeb(image) ? image : ""; this.subtitle=subtitle;
    }
    JSONObject json() throws Exception { return new JSONObject().put("id",id).put("name",name).put("group",group).put("url",url).put("kind",kind).put("image",image).put("subtitle",subtitle).put("number",number); }
    static Entry from(JSONObject j) { return new Entry(j.optString("id"),j.optString("name"),j.optString("group"),j.optString("url"),j.optString("kind"),j.optString("image"),j.optString("subtitle")).withNumber(j.optInt("number",0)); }
    Entry withNumber(int n) { number=n; return this; }
    Entry withSourceNumber(int n) { sourceNumber=n; return this; }
    @Override public String toString() { return name; }
}
