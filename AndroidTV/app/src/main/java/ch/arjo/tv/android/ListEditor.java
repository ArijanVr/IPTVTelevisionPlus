package ch.arjo.tv.android;

import android.app.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import java.util.*;

/** «Meine Listen»: Kategorien und Sender ein-/ausblenden, umbenennen und ordnen, Aufbau der Startseite und Kacheln. Wirkt sofort. */
final class ListEditor extends LinearLayout {
    interface Host { List<Entry> all(); Set<String> favorites(); void toggleFavorite(Entry e); void changed(); void close(); }
    private final Activity activity;
    private final Lists lists;
    private final Host host;
    private final Map<String,Button> tabs=new LinkedHashMap<>();
    private final LinearLayout rows;
    private final ScrollView scroll;
    private String page="categories",area="live",group="";

    ListEditor(Activity a,Lists lists,String start,Host host){
        super(a);activity=a;this.lists=lists;this.host=host;page=start;setOrientation(VERTICAL);int sx=Math.max(Math.round(a.getResources().getDisplayMetrics().widthPixels*0.05f),TvStyle.dp(a,32));setPadding(sx,TvStyle.dp(a,8),sx,TvStyle.dp(a,8)+Math.round(a.getResources().getDisplayMetrics().heightPixels*0.05f));
        LinearLayout top=TvStyle.row(a);top.setGravity(Gravity.CENTER_VERTICAL);
        Button back=TvStyle.button(a,"‹ Zurück",host::close);top.addView(back,new LayoutParams(-2,d(40)));
        TextView title=TvStyle.title(a,"",28);title.setText("Meine Listen");
        LayoutParams tp=new LayoutParams(0,-2,1);tp.leftMargin=d(18);top.addView(title,tp);
        String[] keys={"categories","channels","home"},labels={"Kategorien","Sender","Jetzt"};
        for(int i=0;i<keys.length;i++){String key=keys[i];Button b=TvStyle.button(a,labels[i],()->{page=key;render(true);});LayoutParams p=new LayoutParams(-2,d(40));p.leftMargin=d(8);top.addView(b,p);tabs.put(key,b);}
        addView(top,new LayoutParams(-1,-2));
        scroll=new ScrollView(a);scroll.setClipToPadding(false);scroll.setPadding(0,d(14),0,d(24));rows=TvStyle.column(a);scroll.addView(rows);addView(scroll,new LayoutParams(-1,0,1));
        render(true);
    }
    private int d(int n){return TvStyle.dp(activity,n);}
    String page(){return page;}

    /** Baut die Zeilen neu und behält den Fokus an derselben Stelle (Fernbedienung). */
    private void render(boolean focusTab){
        int focused=-1;for(int i=0;i<rows.getChildCount();i++)if(rows.getChildAt(i).hasFocus())focused=i;
        tabs.forEach((k,b)->b.setSelected(k.equals(page)));rows.removeAllViews();
        if(page.equals("categories"))categories();else if(page.equals("channels"))channels();else home();
        if(focusTab)tabs.get(page).requestFocus();
        else if(rows.getChildCount()>0)rows.getChildAt(Math.max(0,Math.min(focused,rows.getChildCount()-1))).requestFocus();
    }
    private void changed(){host.changed();render(false);}

    private void categories(){
        rows.addView(picker("Bereich: "+Lists.areaLabel(area)+" ⌄",()->choose("Bereich",Lists.AREA_LABELS,n->{area=Lists.AREAS[n];render(false);})));
        List<String> groups=lists.ordered(area,groupsOf(area));int hidden=0;for(String g:groups)if(lists.groupHidden(area,g))hidden++;
        note((groups.size()-hidden)+" von "+groups.size()+" sichtbar · OK: ein-/ausblenden · OK halten: umbenennen, verschieben");
        for(String g:groups){boolean off=lists.groupHidden(area,g);
            rows.addView(row(lists.groupName(area,g),off?"Ausgeblendet":"Sichtbar",off,()->{lists.setGroupHidden(area,g,!off);changed();},()->choose(lists.groupName(area,g),new String[]{"Umbenennen …","Nach oben","Nach unten"},n->{
                if(n==0)rename(lists.groupName(area,g),name->{lists.renameGroup(area,g,name);changed();});else{lists.move(area,groups,g,n==1?-1:1);changed();}
            })));}
        if(groups.isEmpty())note("Noch keine Kategorien geladen.");
        if(lists.customOrder(area))rows.addView(picker("Reihenfolge des Anbieters wiederherstellen",()->{lists.resetOrder(area);changed();}));
    }
    private void channels(){
        List<String> groups=lists.ordered("live",groupsOf("live"));
        if(!groups.contains(group))group=host.favorites().isEmpty()&&!groups.isEmpty()?groups.get(0):"";
        rows.addView(picker("Liste: "+(group.isEmpty()?"★ Favoriten":lists.groupName("live",group))+" ⌄",()->{
            String[] names=new String[groups.size()+1];names[0]="★ Favoriten";for(int i=0;i<groups.size();i++)names[i+1]=lists.groupName("live",groups.get(i));
            choose("Liste",names,n->{group=n==0?"":groups.get(n-1);render(false);});
        }));
        List<Entry> shown=new ArrayList<>();for(Entry e:host.all())if(e.kind.equals("live")&&(group.isEmpty()?host.favorites().contains(e.id):e.group.equals(group)))shown.add(e);
        int hidden=0;for(Entry e:shown)if(lists.channelHidden(e))hidden++;
        note((shown.size()-hidden)+" von "+shown.size()+" sichtbar · OK: ein-/ausblenden · OK halten: Favorit, umbenennen");
        for(Entry e:shown){boolean off=lists.channelHidden(e),fav=host.favorites().contains(e.id);
            rows.addView(row((fav?"★ ":"")+lists.name(e),off?"Ausgeblendet":"Sichtbar",off,()->{lists.setHidden(e,!off);changed();},()->choose(lists.name(e),new String[]{fav?"Aus Favoriten entfernen":"Zu Favoriten hinzufügen","Umbenennen …"},n->{
                if(n==0){host.toggleFavorite(e);changed();}else rename(lists.name(e),name->{lists.rename(e,name);changed();});
            })));}
        if(shown.isEmpty())note(group.isEmpty()?"Noch keine Favoriten. OK halten auf einem Sender: «Zu Favoriten hinzufügen».":"Keine Sender in dieser Kategorie.");
    }
    private void home(){
        rows.addView(row("Sendernamen unter den Kacheln",lists.showNames()?"Ein":"Aus",false,()->{lists.setShowNames(!lists.showNames());changed();},null));
        rows.addView(row("Kachelgrösse",Lists.SIZES[lists.tileSize()],false,()->{lists.setTileSize((lists.tileSize()+1)%3);changed();},null));
        note("Reihen von «Jetzt» · OK: ein-/ausblenden · OK halten: verschieben");
        for(String s:lists.homeOrder()){boolean off=lists.sectionHidden(s);
            rows.addView(row(Lists.sectionLabel(s),off?"Ausgeblendet":"Sichtbar",off,()->{lists.setSectionHidden(s,!off);changed();},()->choose(Lists.sectionLabel(s),new String[]{"Nach oben","Nach unten"},n->{lists.moveSection(s,n==0?-1:1);changed();})));}
        rows.addView(picker("Standard-Aufbau wiederherstellen",()->{lists.resetHome();changed();}));
    }

    private Collection<String> groupsOf(String area){LinkedHashSet<String> out=new LinkedHashSet<>();for(Entry e:host.all())if(Lists.area(e).equals(area))out.add(e.group);return out;}
    private View row(String name,String value,boolean off,Runnable click,Runnable hold){
        LinearLayout row=TvStyle.row(activity);row.setGravity(Gravity.CENTER_VERTICAL);TvStyle.pad(activity,row,18,10);
        TextView eye=TvStyle.text(activity,off?"○":"●",18);eye.setTextColor(off?TvStyle.SECONDARY:TvStyle.WHITE);row.addView(eye,new LayoutParams(d(30),-2));
        TextView label=TvStyle.title(activity,name,17);label.setMaxLines(1);label.setEllipsize(TextUtils.TruncateAt.END);label.setAlpha(off?.55f:1);row.addView(label,new LayoutParams(0,-2,1));
        TextView state=TvStyle.text(activity,value,14);state.setTextColor(TvStyle.SECONDARY);row.addView(state);
        TvStyle.cardFocus(row,null);row.setContentDescription(name+", "+value);row.setOnClickListener(v->click.run());
        if(hold!=null)row.setOnLongClickListener(v->{hold.run();return true;});
        row.setLayoutParams(rowParams());return row;
    }
    private View picker(String label,Runnable action){Button b=TvStyle.button(activity,label,action);b.setGravity(Gravity.LEFT|Gravity.CENTER_VERTICAL);LayoutParams p=new LayoutParams(-2,d(42));p.bottomMargin=d(10);b.setLayoutParams(p);return b;}
    private LayoutParams rowParams(){LayoutParams p=new LayoutParams(-1,-2);p.bottomMargin=d(8);return p;}
    private void note(String text){TextView v=TvStyle.text(activity,text,14);v.setTextColor(TvStyle.SECONDARY);v.setPadding(0,d(4),0,d(10));v.setFocusable(false);rows.addView(v);}
    private interface Pick { void index(int n); }
    private void choose(String title,String[] items,Pick pick){new AlertDialog.Builder(activity).setTitle(title).setItems(items,(dialog,n)->pick.index(n)).setNegativeButton("Abbrechen",null).show();}
    private interface Named { void name(String value); }
    private void rename(String current,Named done){
        EditText field=new EditText(activity);field.setText(current);field.setSingleLine(true);field.setSelectAllOnFocus(true);
        new AlertDialog.Builder(activity).setTitle("Umbenennen").setMessage("Leer lassen, um den Originalnamen wiederherzustellen.").setView(field)
            .setPositiveButton("Sichern",(dialog,n)->done.name(field.getText().toString())).setNegativeButton("Abbrechen",null).show();
    }
}
