package ch.arjo.tv.android;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.text.*;
import android.view.*;
import android.widget.*;
import androidx.recyclerview.widget.*;
import org.json.JSONObject;
import java.util.*;

/** Original ARJO hierarchy: featured title, horizontal channel rows and 2:3 film posters. */
final class LibraryView extends LinearLayout {
    interface Actions {
        void navigate(String kind); void open(Entry entry); void play(Entry entry); void menu(Entry entry);
        void search(String query); void action(String action);
    }
    interface Progress { long position(Entry e); float fraction(Entry e); }
    private final Activity activity;
    private final Artwork artwork;
    private final Actions actions;
    private final Progress progress;
    private final Map<String,Button> tabs=new LinkedHashMap<>();
    private final TextView title,status;
    private final LinearLayout tools;
    private final RecyclerView content;
    private final FrameLayout stage;
    private final EditText search;
    private final List<Section> sections=new ArrayList<>();
    /** Ein Pool für alle Reihen: Karten werden beim Scrollen wiederverwendet statt neu gebaut. */
    private final RecyclerView.RecycledViewPool cards=new RecyclerView.RecycledViewPool();
    private List<Entry> entries=new ArrayList<>(),history=new ArrayList<>();
    private Set<String> favorites=new HashSet<>();
    private String kind="home",selectedGroup="Alle",query="",mode="Sender";
    private boolean favoriteOnly, split;
    /** Zweigeteilte Ansicht (Filme, Serien, Live-Kategorien): links Kategorien, rechts Raster der fokussierten Kategorie. */
    private final LinearLayout splitView;
    private final RecyclerView catList,gridView;
    private final CategoryAdapter catAdapter=new CategoryAdapter();
    private final CardAdapter gridAdapter=new CardAdapter(true);
    private final android.os.Handler handler=new android.os.Handler(android.os.Looper.getMainLooper());
    private final Runnable applyCategory=this::refreshGrid;
    private LinkedHashMap<String,List<Entry>> splitGroups=new LinkedHashMap<>();
    private List<Entry> splitAll=new ArrayList<>();
    private String splitSignature="";
    private int lastGridPos;
    private Entry detail,heroEntry;
    private int heroIndex;
    private List<Entry> heroItems=new ArrayList<>();
    private View detailView;
    private TextView detailPlot;
    private LinearLayout episodeHost;
    private final Map<String,List<Entry>> seasons=new LinkedHashMap<>();
    private String selectedSeason="";
    private Lists lists;

    LibraryView(Activity a,Artwork artwork,Actions actions,Progress progress) {
        super(a); activity=a; this.artwork=artwork; this.actions=actions; this.progress=progress; lists=new Lists(a.getSharedPreferences("library",0),"");cards.setMaxRecycledViews(0,40);cards.setMaxRecycledViews(1,40);
        setOrientation(VERTICAL); setBackgroundColor(TvStyle.BLACK); setClipChildren(false);
        // Sicherer Fernsehrand: 80 px seitlich und 60 px oben/unten bei 1920 x 1080 (Google TV): Texte und Bedienelemente bleiben im Rand, Flächen und Reihen laufen bis zum Bildschirmrand
        // und werden nicht abgeschnitten. Deshalb gibt es kein Padding am Wurzelelement.
        ox=Math.round(TvStyle.px(a,80));oy=Math.round(TvStyle.px(a,60));
        FrameLayout header=new FrameLayout(a); header.setPadding(Math.max(ox,d(28)),Math.max(oy,d(14)),Math.max(ox,d(28)),d(14));
        LinearLayout branding=TvStyle.row(a);branding.setGravity(Gravity.CENTER_VERTICAL);header.addView(branding,new FrameLayout.LayoutParams(-2,-2,Gravity.LEFT|Gravity.CENTER_VERTICAL));
        TextView mark=TvStyle.wordmark(a,32); branding.addView(mark,new LayoutParams(-2,-2));
        LinearLayout nav=TvStyle.row(a);nav.setTag("main_navigation"); nav.setGravity(Gravity.CENTER); nav.setBackground(TvStyle.shape(0xE61A1B1D,TvStyle.DIVIDER,40)); TvStyle.pad(a,nav,4,4);
        // Tabs: Jetzt · Live · Filme · Serien · Mediathek, dazu Suche und Profil.
        String[] keys={"home","live","movie","series","favorites","search","settings"}, labels={"Jetzt","Live","Filme","Serien","Mediathek","Suche","Profil"};
        for (int i=0;i<keys.length;i++) {
            String key=keys[i]; Button b=TvStyle.button(a,labels[i],()->actions.navigate(key)); b.setTextSize(14); b.setPadding(d(13),0,d(13),0);
            nav.addView(b,new LayoutParams(-2,d(40))); tabs.put(key,b);
        }
        HorizontalScrollView navigationScroll=new HorizontalScrollView(a);navigationScroll.setHorizontalScrollBarEnabled(false);navigationScroll.addView(nav,new HorizontalScrollView.LayoutParams(-2,-2));FrameLayout.LayoutParams centeredMenu=new FrameLayout.LayoutParams(-2,-2,Gravity.CENTER);centeredMenu.leftMargin=d(125);centeredMenu.rightMargin=d(125);header.addView(navigationScroll,centeredMenu);header.addView(playlistStatus(a),new FrameLayout.LayoutParams(-2,-2,Gravity.RIGHT|Gravity.CENTER_VERTICAL)); addView(header,new LayoutParams(-1,-2));
        tools=TvStyle.row(a); tools.setGravity(Gravity.CENTER_VERTICAL); tools.setPadding(Math.max(ox,d(32)),d(6),Math.max(ox,d(32)),d(6));
        title=TvStyle.title(a,"Jetzt",28); tools.addView(title,new LayoutParams(0,d(44),1)); addView(tools,new LayoutParams(-1,-2));
        search=new EditText(a); search.setHint("Sender, Filme und Serien suchen"); search.setSingleLine(true); search.setTextSize(18); search.setTextColor(TvStyle.WHITE); search.setHintTextColor(TvStyle.SECONDARY);
        search.setBackground(TvStyle.inputBackground(a)); TvStyle.pad(a,search,16,12); search.setId(View.generateViewId()); search.setSaveEnabled(false);
        search.addTextChangedListener(new TextWatcher() { public void beforeTextChanged(CharSequence s,int start,int count,int after){} public void afterTextChanged(Editable e){} public void onTextChanged(CharSequence s,int start,int before,int count){query=s.toString(); actions.search(query);} });
        LayoutParams searchParams=new LayoutParams(-1,d(52)); searchParams.setMargins(Math.max(ox,d(32)),d(8),Math.max(ox,d(32)),d(12)); addView(search,searchParams); search.setVisibility(GONE);
        stage=new FrameLayout(a); addView(stage,new LayoutParams(-1,0,1));
        content=new RecyclerView(a); content.setLayoutManager(new LinearLayoutManager(a)); content.setItemAnimator(null); content.setClipToPadding(false); content.setClipChildren(false); content.setPadding(Math.max(0,ox-d(32)),d(2),0,d(24)+oy+d(12)); content.setId(View.generateViewId());
        content.setAdapter(new SectionAdapter()); stage.addView(content,new FrameLayout.LayoutParams(-1,-1));
        status=TvStyle.text(a,"",12); status.setTextColor(TvStyle.SECONDARY); status.setPadding(Math.max(ox,d(32)),d(36),Math.max(ox,d(32)),oy);
        status.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0x00090A0A,0xE6090A0A,0xFF090A0A}));
        int below=d(24)+oy+d(12),side=Math.max(ox,d(32));
        splitView=TvStyle.row(a);splitView.setVisibility(GONE);
        catList=new RecyclerView(a);catList.setLayoutManager(new LinearLayoutManager(a));catList.setItemAnimator(null);catList.setClipToPadding(false);catList.setClipChildren(false);catList.setPadding(side,d(8),d(8),below);catList.setId(View.generateViewId());catList.setAdapter(catAdapter);
        splitView.addView(catList,new LayoutParams(side+d(8)+Math.round(TvStyle.px(a,400)),-1));
        gridView=new RecyclerView(a);gridView.setLayoutManager(new GridLayoutManager(a,5));gridView.setItemAnimator(null);gridView.setClipToPadding(false);gridView.setClipChildren(false);gridView.setPadding(d(16),d(8),side,below);gridView.setId(View.generateViewId());gridView.setAdapter(gridAdapter);
        splitView.addView(gridView,new LayoutParams(0,-1,1));
        stage.addView(splitView,new FrameLayout.LayoutParams(-1,-1));
        stage.addView(status,new FrameLayout.LayoutParams(-1,-2,Gravity.BOTTOM));
    }
    private int ox,oy;
    private View healthDot;
    private String statusText="",expiryText="";
    /** Rechts oben: Status-Punkt (Punkt = Playlist aktiv, Ring = Problem) und Aktualisieren-Button; das Ablaufdatum steht in der Statuszeile unten. */
    private LinearLayout playlistStatus(Activity a) {
        LinearLayout box=TvStyle.row(a);box.setGravity(Gravity.CENTER_VERTICAL);
        healthDot=new View(a);healthDot.setBackground(dot(0));healthDot.setContentDescription("Playlist wird geprüft");
        LayoutParams dotParams=new LayoutParams(d(12),d(12));dotParams.setMargins(d(10),0,d(10),0);box.addView(healthDot,dotParams);
        Button refresh=TvStyle.button(a,"↻",()->actions.action("reload"));refresh.setContentDescription("Playlist aktualisieren");refresh.setTextSize(14);refresh.setPadding(d(13),0,d(13),0);
        box.addView(refresh,new LayoutParams(-2,d(40)));
        return box;
    }
    /** Status-Punkt: gefüllt = aktiv, Ring = Problem (Glut), grau = unbekannt. Form und Beschriftung tragen die Bedeutung, nicht nur die Farbe. */
    private GradientDrawable dot(int state){GradientDrawable g=new GradientDrawable();g.setShape(GradientDrawable.OVAL);
        if(state<0){g.setColor(Color.TRANSPARENT);g.setStroke(Math.max(2,d(2)),TvStyle.GLUT);}else g.setColor(state>0?TvStyle.GLUT:TvStyle.BORDER);return g;}
    /** @param state 1 = aktiv (Punkt), -1 = Problem (Ring), 0 = unbekannt (grau). @param expirySeconds Ablauf des Abos, 0 = unbekannt. */
    void setHealth(int state,String problem,long expirySeconds) {
        healthDot.setBackground(dot(state));
        healthDot.setContentDescription(state>0?"Playlist aktiv":state<0?"Playlist-Problem: "+problem:"Playlist wird geprüft");
        long left=expirySeconds*1000-System.currentTimeMillis();
        expiryText=expirySeconds<=0?"":left<=0?"Abo abgelaufen":"Gültig bis "+new java.text.SimpleDateFormat("dd.MM.yyyy",Locale.GERMANY).format(new Date(expirySeconds*1000));
        setStatus(statusText);
    }
    private int fontExtra(int amount){return Math.max(0,Math.round((getResources().getConfiguration().fontScale-1)*amount));}
    private int d(int value) { return TvStyle.dp(activity,value); }
    private static String label(String value) {
        switch(value) { case "home":return "Jetzt"; case "live":return "Live"; case "movie":return "Filme"; case "series":return "Serien"; case "search":return "Suche"; case "favorites":return "Mediathek"; default:return "Einstellungen"; }
    }
    void activate(String next) {
        if (hasDetail()) closeDetail();
        boolean changed=!kind.equals(next); kind=next;
        if(changed) { selectedGroup="Alle"; favoriteOnly=false; query=""; mode="Sender"; search.setText(""); heroIndex=0; }
        tabs.forEach((key,b)->b.setSelected(key.equals(kind)));
        boolean byCategory=kind.equals("movie")||kind.equals("series")||(kind.equals("live")&&mode.equals("Kategorien"));
        title.setText(byCategory?label(kind)+" · Kategorien":label(kind)); tools.setVisibility(kind.equals("home") ? GONE:VISIBLE);
        search.setVisibility(kind.equals("search") ? VISIBLE:GONE);
        View focused=tools.findFocus();String focusedTool=focused instanceof TextView ? ((TextView)focused).getText().toString():null;
        while(tools.getChildCount()>1) tools.removeViewAt(1);
        if(kind.equals("live")) {
            Button channels=TvStyle.button(activity,"Sender",()->{mode="Sender";activate(kind);render();}); channels.setSelected(mode.equals("Sender")); addTool(channels);
            Button categories=TvStyle.button(activity,"Kategorien",()->{mode="Kategorien";activate(kind);render();}); categories.setSelected(mode.equals("Kategorien")); addTool(categories);
            addTool(TvStyle.button(activity,"▦ Multiview",()->actions.action("multiview")));
        }
        if(kind.equals("live") || kind.equals("movie") || kind.equals("series")) {
            if(kind.equals("live")) addTool(TvStyle.button(activity,selectedGroup.equals("Alle") ? "Alle Gruppen ⌄":lists.groupName(areaOf(kind),selectedGroup)+" ⌄",this::chooseGroup));
            Button fav=TvStyle.button(activity,favoriteOnly?"★ Favoriten":"☆ Favoriten",()->{favoriteOnly=!favoriteOnly;activate(kind);render();}); fav.setSelected(favoriteOnly); addTool(fav);
            addTool(TvStyle.button(activity,"Listen bearbeiten",()->actions.action("lists")));
        }
        if(focusedTool!=null){boolean restored=false;for(int i=1;i<tools.getChildCount();i++){View child=tools.getChildAt(i);if(child instanceof TextView && focusedTool.equals(((TextView)child).getText().toString())){child.requestFocus();restored=true;break;}}if(!restored&&tools.getChildCount()>1)tools.getChildAt(1).requestFocus();}
        if(changed) {content.scrollToPosition(0);lastGridPos=0;}
    }
    private void addTool(Button b) { LayoutParams p=new LayoutParams(-2,d(40));p.leftMargin=d(8);tools.addView(b,p); }
    void setData(List<Entry> entries,Set<String> favorites,List<Entry> history) {
        this.entries=new ArrayList<>(entries);this.favorites=new HashSet<>(favorites);this.history=new ArrayList<>(history);render();
    }
    void setStatus(String text) { statusText=text; status.setText(expiryText.isEmpty()?text:text+" · "+expiryText); }
    void setLists(Lists lists) { this.lists=lists; render(); }
    private String areaOf(String key) { return key.equals("movie")||key.equals("series")?key:"live"; }
    /** Gruppen in der eigenen Reihenfolge aus «Meine Listen». */
    private LinkedHashMap<String,List<Entry>> grouped(List<Entry> source) {
        LinkedHashMap<String,List<Entry>> raw=new LinkedHashMap<>(),out=new LinkedHashMap<>();for(Entry e:source)raw.computeIfAbsent(e.group,k->new ArrayList<>()).add(e);
        for(String g:lists.ordered(areaOf(kind),raw.keySet()))out.put(g,raw.get(g));return out;
    }
    void initialFocus() { tabs.get(kind).requestFocus(); }
    void filter(String text) { query=text; render(); }
    private void chooseGroup() {
        List<String> groups=new ArrayList<>();groups.add("Alle");groups.addAll(grouped(entries).keySet());
        String[] names=new String[groups.size()];for(int i=0;i<names.length;i++)names[i]=i==0?"Alle":lists.groupName(areaOf(kind),groups.get(i));
        new android.app.AlertDialog.Builder(activity).setTitle("Kategorie wählen").setItems(names,(dialog,index)->{
            selectedGroup=groups.get(index);mode="Sender";activate(kind);render();content.scrollToPosition(0);
        }).setNegativeButton("Abbrechen",null).show();
    }
    private List<Entry> ofKind(List<Entry> source,String key) {
        List<Entry> out=new ArrayList<>();for(Entry e:source)if(key.equals("series") ? (e.kind.equals("series")||e.kind.equals("episode")):e.kind.equals(key))out.add(e);return out;
    }
    private List<Entry> limit(List<Entry> source,int count) {return new ArrayList<>(source.subList(0,Math.min(count,source.size())));}
    private List<Entry> favorites(List<Entry> source) {List<Entry> result=new ArrayList<>();for(Entry e:source)if(favorites.contains(e.id))result.add(e);return result;}
    private void rail(String name,List<Entry> list,boolean poster) {if(!list.isEmpty())sections.add(new Section(name,list,poster));}
    private void render() {
        sections.clear();split=false;
        if(kind.equals("settings")) {sections.add(Section.settings());refresh();return;}
        if(kind.equals("home")) {
            List<Entry> resumed=new ArrayList<>();for(Entry e:history)if(!e.kind.equals("live")&&progress.position(e)>1000)resumed.add(e);
            List<Entry> visibleHistory=lists.visible(history);List<Entry> last=limit(ofKind(visibleHistory,"live"),1),fav=favorites(entries);resumed=lists.visible(resumed);
            heroItems=new ArrayList<>();heroItems.addAll(limit(resumed,3));heroItems.addAll(last);
            for(Entry e:ofKind(fav,"live"))if(heroItems.stream().noneMatch(h->h.id.equals(e.id)))heroItems.add(e);
            if(heroItems.isEmpty())heroItems.addAll(limit(ofKind(entries,"live"),4));
            if(heroItems.isEmpty())heroItems.addAll(limit(entries,4));
            // Reihen in der Reihenfolge aus «Meine Listen»; nur echte Inhalte der Quelle, nie mitgelieferte Beispiele.
            for(String section:lists.visibleSections())switch(section){
                case "hero": if(!heroItems.isEmpty()) {heroIndex=Math.min(heroIndex,heroItems.size()-1);heroEntry=heroItems.get(heroIndex);sections.add(Section.hero(heroEntry));} break;
                case "continue": rail("Weiterschauen",resumed,false); break;
                case "last": rail("Zuletzt gesehen",last,false); break;
                case "favorites": rail("Favoriten",fav,false); break;
                case "live": if(fav.isEmpty())rail("Live TV",limit(ofKind(entries,"live"),20),false); break;
                case "movies": rail("Neue Filme",limit(ofKind(entries,"movie"),20),true); break;
                case "series": rail("Neue Serien",limit(ofKind(entries,"series"),20),true); break;
            }
        } else {
            List<Entry> filtered=new ArrayList<>();String term=query.toLowerCase(Locale.ROOT);
            boolean categories=kind.equals("movie")||kind.equals("series")||(kind.equals("live")&&mode.equals("Kategorien"));
            for(Entry e:entries)if((categories||selectedGroup.equals("Alle")||e.group.equals(selectedGroup))&&(!favoriteOnly||favorites.contains(e.id))&&lists.name(e).toLowerCase(Locale.ROOT).contains(term))filtered.add(e);
            if(categories&&!filtered.isEmpty()) {
                split=true;updateSplit(grouped(filtered),filtered);return;
            } else if(kind.equals("search") || kind.equals("favorites")) {
                rail("Sender",ofKind(filtered,"live"),false);rail("Filme",ofKind(filtered,"movie"),true);rail("Serien & Episoden",ofKind(filtered,"series"),true);
            } else if(!categories) {
                grouped(filtered).forEach((name,list)->rail(name,list,!kind.equals("live")));
            }
        }
        if(sections.isEmpty()&&kind.equals("favorites"))sections.add(Section.empty("Noch nichts gemerkt.","Halte OK bei einem Sender, Film oder einer Serie gedrückt und wähle «Favorit». Er erscheint dann hier."));
        if(sections.isEmpty())sections.add(Section.empty(kind.equals("search")?"Keine passenden Inhalte gefunden.":"Hier erscheinen Deine Inhalte.",kind.equals("home")?"Füge Favoriten hinzu oder starte einen Sender, Film oder eine Serie.":"Wähle eine andere Kategorie oder lade die Quelle erneut."));
        refresh();
    }
    private void refresh() {
        content.getAdapter().notifyDataSetChanged();applyStage();
    }
    /** Zeigt die Reihen oder die geteilte Ansicht, ausser eine Detailseite oder ein Panel liegt darüber. */
    private void applyStage(){boolean main=!hasDetail();content.setVisibility(main&&!split?VISIBLE:GONE);splitView.setVisibility(main&&split?VISIBLE:GONE);}
    /** Kategorienliste links, Raster rechts. Bei unveränderten Daten und Fokus in der Ansicht bleibt alles stehen (kein Fokussprung). */
    private void updateSplit(LinkedHashMap<String,List<Entry>> groups,List<Entry> all){
        StringBuilder sig=new StringBuilder(kind+"|"+mode+"|"+favorites.hashCode()+"|"+all.size());for(Map.Entry<String,List<Entry>> g:groups.entrySet())sig.append('|').append(lists.groupName(areaOf(kind),g.getKey())).append(':').append(g.getValue().size());
        boolean same=sig.toString().equals(splitSignature)&&splitView.hasFocus();splitSignature=sig.toString();
        splitGroups=groups;splitAll=all;if(!selectedGroup.equals("Alle")&&!groups.containsKey(selectedGroup))selectedGroup="Alle";
        content.getAdapter().notifyDataSetChanged();applyStage();
        if(same)return;
        catAdapter.update();refreshGrid();
    }
    private void refreshGrid(){
        handler.removeCallbacks(applyCategory);
        List<Entry> list=selectedGroup.equals("Alle")?splitAll:splitGroups.get(selectedGroup);if(list==null)list=Collections.emptyList();
        boolean poster=!kind.equals("live");((GridLayoutManager)gridView.getLayoutManager()).setSpanCount(poster?5:4);
        gridAdapter.update(list,poster);gridView.scrollToPosition(0);lastGridPos=0;
    }
    /** Fokus auf eine Kategorie: Auswahl sofort markieren, das Raster leicht entprellt nachführen. */
    private void selectCategory(String group){
        if(group.equals(selectedGroup)&&gridAdapter.getItemCount()>0)return;
        selectedGroup=group;catAdapter.markSelected();handler.removeCallbacks(applyCategory);handler.postDelayed(applyCategory,150);
    }
    private boolean focusGrid(){
        boolean pending=false;if(selectedGroup!=null&&gridAdapter.lastGroup!=null&&!gridAdapter.lastGroup.equals(selectedGroup)){refreshGrid();pending=true;}
        if(gridAdapter.getItemCount()==0)return false;
        if(pending){gridView.post(this::focusGridNow);return true;}
        return focusGridNow();
    }
    private boolean focusGridNow(){
        int pos=Math.max(0,Math.min(lastGridPos,gridAdapter.getItemCount()-1));RecyclerView.ViewHolder h=gridView.findViewHolderForAdapterPosition(pos);
        if(h!=null)return h.itemView.requestFocus();
        gridView.scrollToPosition(pos);gridView.post(()->{RecyclerView.ViewHolder later=gridView.findViewHolderForAdapterPosition(pos);if(later!=null)later.itemView.requestFocus();});return true;
    }
    private boolean focusList(){
        int index=Math.max(0,catAdapter.names.indexOf(selectedGroup));RecyclerView.ViewHolder h=catList.findViewHolderForAdapterPosition(index);
        if(h!=null)return h.itemView.requestFocus();
        catList.scrollToPosition(index);catList.post(()->{RecyclerView.ViewHolder later=catList.findViewHolderForAdapterPosition(index);if(later!=null)later.itemView.requestFocus();});return true;
    }
    private void focusMain(){
        if(!split){content.requestFocus();return;}
        gridView.post(()->{if(hasDetail()||!split)return;RecyclerView.ViewHolder h=gridView.findViewHolderForAdapterPosition(lastGridPos);if(h==null||!h.itemView.requestFocus())focusList();});
    }
    private final class CategoryAdapter extends RecyclerView.Adapter<RecyclerView.ViewHolder> {
        List<String> names=new ArrayList<>();
        void update(){names=new ArrayList<>();names.add("Alle");names.addAll(splitGroups.keySet());notifyDataSetChanged();}
        void markSelected(){for(int i=0;i<catList.getChildCount();i++){View row=catList.getChildAt(i);row.setSelected(selectedGroup.equals(row.getTag()));}}
        @Override public int getItemCount(){return names.size();}
        @Override public RecyclerView.ViewHolder onCreateViewHolder(ViewGroup parent,int type){
            LinearLayout row=TvStyle.row(activity);row.setGravity(Gravity.CENTER_VERTICAL);row.setPadding(d(20),0,d(20),0);
            TextView name=TvStyle.title(activity,"",20);name.setMaxLines(1);name.setEllipsize(TextUtils.TruncateAt.END);row.addView(name,new LayoutParams(0,-2,1));
            TextView count=TvStyle.text(activity,"",14);count.setTextColor(TvStyle.TEXT2);LayoutParams cp=new LayoutParams(-2,-2);cp.leftMargin=d(12);row.addView(count,cp);
            android.content.Context c=activity;android.graphics.drawable.StateListDrawable bg=new android.graphics.drawable.StateListDrawable();
            bg.addState(new int[]{android.R.attr.state_focused},TvStyle.focusShape(c,TvStyle.GRAPHITE,TvStyle.R_CONTROL));
            bg.addState(new int[]{android.R.attr.state_selected},TvStyle.shapePx(TvStyle.GRAPHITE,TvStyle.BORDER,TvStyle.radiusPx(c,TvStyle.R_CONTROL),1));
            bg.addState(new int[]{},new android.graphics.drawable.ColorDrawable(Color.TRANSPARENT));
            row.setBackground(bg);row.setFocusable(true);row.setClickable(true);row.setId(View.generateViewId());row.setDefaultFocusHighlightEnabled(false);
            RecyclerView.LayoutParams p=new RecyclerView.LayoutParams(-1,Math.round(TvStyle.px(activity,72)));p.bottomMargin=d(6);row.setLayoutParams(p);
            return new RecyclerView.ViewHolder(row){};
        }
        @Override public void onBindViewHolder(RecyclerView.ViewHolder holder,int position){
            String group=names.get(position);LinearLayout row=(LinearLayout)holder.itemView;boolean all=position==0;
            int size=all?splitAll.size():splitGroups.get(group).size();String label=all?"Alle":lists.groupName(areaOf(kind),group);
            ((TextView)row.getChildAt(0)).setText(label);((TextView)row.getChildAt(1)).setText(String.valueOf(size));
            row.setTag(group);row.setSelected(group.equals(selectedGroup));row.setContentDescription(label+", "+size);
            row.setOnFocusChangeListener((v,hasFocus)->{if(hasFocus)selectCategory(group);});
            row.setOnClickListener(v->focusGrid());
            row.setOnKeyListener((v,code,event)->code==KeyEvent.KEYCODE_DPAD_RIGHT&&event.getAction()==KeyEvent.ACTION_DOWN&&focusGrid());
        }
    }
    private static final class Section {
        String name,description="";List<Entry> list;boolean poster;int type;
        Section(String name,List<Entry> list,boolean poster){this.name=name;this.list=list;this.poster=poster;}
        static Section hero(Entry entry){Section s=new Section("",Collections.singletonList(entry),false);s.type=1;return s;}
        static Section empty(String name,String description){Section s=new Section(name,Collections.emptyList(),false);s.type=3;s.description=description;return s;}
        static Section settings(){Section s=new Section("Einstellungen",Collections.emptyList(),false);s.type=4;return s;}
    }
    private final class SectionAdapter extends RecyclerView.Adapter<RecyclerView.ViewHolder> {
        @Override public int getItemCount(){return sections.size();}
        @Override public int getItemViewType(int position){return sections.get(position).type;}
        @Override public RecyclerView.ViewHolder onCreateViewHolder(ViewGroup parent,int type){
            if(type==0)return new RailHolder();
            FrameLayout frame=new FrameLayout(activity);frame.setLayoutParams(new RecyclerView.LayoutParams(-1,-2));return new RecyclerView.ViewHolder(frame){};
        }
        @Override public void onBindViewHolder(RecyclerView.ViewHolder holder,int position){
            Section s=sections.get(position);
            if(holder instanceof RailHolder){((RailHolder)holder).bind(s);return;}
            FrameLayout frame=(FrameLayout)holder.itemView;frame.removeAllViews();
            if(s.type==1){frame.addView(hero(s.list.get(0)),new FrameLayout.LayoutParams(-1,d(340+fontExtra(130))));}
            if(s.type==3){LinearLayout empty=TvStyle.column(activity);TvStyle.pad(activity,empty,32,46);empty.addView(TvStyle.title(activity,s.name,24));TextView note=TvStyle.text(activity,s.description,17);note.setTextColor(TvStyle.SECONDARY);note.setPadding(0,d(12),0,d(24));empty.addView(note);empty.addView(TvStyle.button(activity,"Quelle neu laden",()->actions.action("reload")),new LayoutParams(-2,d(46)));frame.addView(empty);}
            if(s.type==4)frame.addView(settingsPanel());
        }
    }
    private final class RailHolder extends RecyclerView.ViewHolder {
        final TextView heading;final RecyclerView rail;final CardAdapter adapter=new CardAdapter(false);String bound;
        RailHolder(){super(TvStyle.column(activity));LinearLayout box=(LinearLayout)itemView;box.setClipChildren(false);
            heading=TvStyle.title(activity,"",20);TvStyle.pad(activity,heading,32,4);box.addView(heading);
            rail=new RecyclerView(activity);LinearLayoutManager layout=new LinearLayoutManager(activity,RecyclerView.HORIZONTAL,false);layout.setInitialPrefetchItemCount(5);rail.setLayoutManager(layout);rail.setItemAnimator(null);rail.setClipToPadding(false);rail.setClipChildren(false);rail.setPadding(d(28),d(10),d(28),d(16));rail.setNestedScrollingEnabled(false);rail.setHasFixedSize(true);rail.setRecycledViewPool(cards);rail.setAdapter(adapter);box.addView(rail,new LayoutParams(-1,d(180)));box.setLayoutParams(new RecyclerView.LayoutParams(-1,-2));
        }
        void bind(Section s){boolean groupRow=!kind.equals("home")&&!kind.equals("search")&&!kind.equals("favorites");heading.setText(groupRow?lists.groupName(areaOf(kind),s.name):s.name);
            int tile=lists.tileWidth()*9/16+(lists.showNames()?58+fontExtra(30):0)+34;int height=d(s.poster?312+fontExtra(60):tile);if(rail.getLayoutParams().height!=height){rail.getLayoutParams().height=height;rail.requestLayout();}
            boolean same=s.name.equals(bound)&&adapter.poster==s.poster;bound=s.name;adapter.update(s.list,s.poster);if(!same)rail.scrollToPosition(0);}
    }
    private final class CardAdapter extends RecyclerView.Adapter<CardHolder> {
        List<Entry> list=Collections.emptyList();boolean poster;final boolean fluid;String lastGroup;
        CardAdapter(boolean fluid){this.fluid=fluid;setHasStableIds(true);}
        void update(List<Entry> next,boolean poster){this.list=next;this.poster=poster;lastGroup=selectedGroup;notifyDataSetChanged();}
        // Günstige stabile ID (kein SHA-256 pro Karte beim Scrollen).
        @Override public long getItemId(int position){String id=list.get(position).id;return ((long)id.hashCode()<<32)^id.length();}
        @Override public int getItemCount(){return list.size();}
        @Override public int getItemViewType(int position){return poster?1:0;}
        @Override public CardHolder onCreateViewHolder(ViewGroup p,int type){return new CardHolder(type==1,fluid);}
        @Override public void onBindViewHolder(CardHolder holder,int index){holder.bind(list.get(index));}
    }
    /** Karte: Poster (2:3) oder 16:9-Fläche, bei Sendern mit dem Logo gross in der Mitte. Fokusring nur um die Bildfläche, Name darunter (abschaltbar). */
    private final class CardHolder extends RecyclerView.ViewHolder {
        final LinearLayout card;final FrameLayout frame;final ImageView image;final TextView name,meta,caption;final ProgressBar bar;final boolean poster,fluid;
        CardHolder(boolean poster,boolean fluid){
            super(TvStyle.column(activity));this.poster=poster;this.fluid=fluid;card=(LinearLayout)itemView;card.setClipChildren(false);card.setClipToPadding(false);TvStyle.pad(activity,card,6,6);
            int width=poster?144:lists.tileWidth();RecyclerView.LayoutParams p=new RecyclerView.LayoutParams(fluid?-1:d(width),-2);p.setMargins(fluid?d(8):d(5),d(4),fluid?d(8):d(9),d(4));card.setLayoutParams(p);
            frame=fluid?new AspectFrame(activity,poster?1.5f:9f/16f):new FrameLayout(activity);frame.setDuplicateParentStateEnabled(true);frame.setClipToOutline(true);
            android.graphics.drawable.StateListDrawable ring=new android.graphics.drawable.StateListDrawable();ring.addState(new int[]{android.R.attr.state_focused},TvStyle.focusRing(activity,TvStyle.R_CARD));ring.addState(new int[]{},TvStyle.shapePx(0,0x14FDFDFC,TvStyle.radiusPx(activity,TvStyle.R_CARD),1));
            frame.setForeground(ring);frame.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{TvStyle.GRAPHITE,TvStyle.RAISED}){{setCornerRadius(TvStyle.radiusPx(activity,TvStyle.R_CARD));}});
            card.addView(frame,new LayoutParams(-1,fluid?-2:d(poster?198:width*9/16)));
            image=new ImageView(activity);frame.addView(image,new FrameLayout.LayoutParams(-1,-1));
            bar=new ProgressBar(activity,null,android.R.attr.progressBarStyleHorizontal);bar.setProgressTintList(android.content.res.ColorStateList.valueOf(TvStyle.GLUT));bar.setProgressBackgroundTintList(android.content.res.ColorStateList.valueOf(0x40FFFFFF));bar.setMax(1000);
            frame.addView(bar,new FrameLayout.LayoutParams(-1,d(4),Gravity.BOTTOM));
            caption=TvStyle.title(activity,"",13);caption.setBackground(TvStyle.shape(0x99090A0A,0,40));TvStyle.pad(activity,caption,10,4);caption.setMaxLines(1);caption.setEllipsize(TextUtils.TruncateAt.END);caption.setVisibility(GONE);
            FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.LEFT);cp.setMargins(d(8),0,d(8),d(10));frame.addView(caption,cp);
            name=TvStyle.title(activity,"",14);name.setMaxLines(poster?2:1);name.setEllipsize(TextUtils.TruncateAt.END);LayoutParams nameParams=new LayoutParams(-1,-2);nameParams.topMargin=d(8);card.addView(name,nameParams);
            meta=TvStyle.text(activity,"",12);meta.setMaxLines(1);meta.setEllipsize(TextUtils.TruncateAt.END);meta.setTextColor(TvStyle.SECONDARY);LayoutParams metaParams=new LayoutParams(-1,-2);metaParams.topMargin=d(4);card.addView(meta,metaParams);
            card.setFocusable(true);card.setClickable(true);card.setId(View.generateViewId());card.setDefaultFocusHighlightEnabled(false);
            TvStyle.scaleOnFocus(card,null,focused->{caption.setVisibility(focused&&caption.getText().length()>0?VISIBLE:GONE);TvStyle.glow(frame,focused);if(fluid&&focused){int pos=getAdapterPosition();if(pos>=0)lastGridPos=pos;}},TvStyle.CARD_SCALE);
            if(fluid)card.setOnKeyListener((v,code,event)->{
                if(code!=KeyEvent.KEYCODE_DPAD_LEFT||event.getAction()!=KeyEvent.ACTION_DOWN)return false;
                int pos=getAdapterPosition(),columns=((GridLayoutManager)gridView.getLayoutManager()).getSpanCount();return pos>=0&&pos%columns==0&&focusList();
            });
        }
        void bind(Entry e){
            int width=d(poster?144:lists.tileWidth());if(!fluid&&card.getLayoutParams().width!=width){card.getLayoutParams().width=width;frame.getLayoutParams().height=poster?d(198):width*9/16;card.requestLayout();}
            boolean live=e.kind.equals("live"),names=poster||!live||lists.showNames();String title=(live&&e.number>0?e.number+"  ":"")+lists.name(e);
            artwork.load(image,e.image,live);int inset=live?d(Math.max(10,lists.tileWidth()/10)):0;image.setPadding(inset,inset*3/4,inset,inset*3/4);
            name.setText((favorites.contains(e.id)?"★ ":"")+title);meta.setText(e.subtitle.isEmpty()?(live?lists.groupName("live",e.group):""):e.subtitle);
            name.setVisibility(names?VISIBLE:GONE);meta.setVisibility(names?VISIBLE:GONE);caption.setText(names?"":title);
            float fraction=progress.fraction(e);bar.setVisibility(fraction>0?VISIBLE:GONE);bar.setProgress((int)(fraction*1000));
            card.setContentDescription(title+(favorites.contains(e.id)?", Favorit":""));card.setOnClickListener(v->actions.open(e));card.setOnLongClickListener(v->{actions.menu(e);return true;});
        }
    }
    /** Fläche mit festem Seitenverhältnis (Höhe = Breite x ratio): 2:3-Poster oder 16:9-Kachel im Raster. */
    private static final class AspectFrame extends FrameLayout {
        private final float ratio;
        AspectFrame(Activity a,float ratio){super(a);this.ratio=ratio;}
        @Override protected void onMeasure(int w,int h){int width=MeasureSpec.getSize(w);super.onMeasure(MeasureSpec.makeMeasureSpec(width,MeasureSpec.EXACTLY),MeasureSpec.makeMeasureSpec(Math.round(width*ratio),MeasureSpec.EXACTLY));}
    }
    private View hero(Entry e){
        FrameLayout hero=new FrameLayout(activity);hero.setBackgroundColor(TvStyle.RAISED);
        ImageView backdrop=new ImageView(activity);artwork.load(backdrop,e.image,false);backdrop.setScaleType(ImageView.ScaleType.CENTER_CROP);backdrop.setAlpha(.6f);hero.addView(backdrop,new FrameLayout.LayoutParams(-1,-1));
        View horizontal=new View(activity);horizontal.setBackground(new GradientDrawable(GradientDrawable.Orientation.LEFT_RIGHT,new int[]{TvStyle.BLACK,0xE6090A0A,0x40090A0A}));hero.addView(horizontal,new FrameLayout.LayoutParams(-1,-1));
        View fade=new View(activity);fade.setBackground(new GradientDrawable(GradientDrawable.Orientation.TOP_BOTTOM,new int[]{0x00090A0A,0x60090A0A,TvStyle.BLACK}));hero.addView(fade,new FrameLayout.LayoutParams(-1,-1));
        if(e.kind.equals("live")){
            ImageView logo=new ImageView(activity);artwork.load(logo,e.image,true);FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(d(235),d(140),Gravity.RIGHT|Gravity.TOP);lp.setMargins(0,d(30),d(50),0);hero.addView(logo,lp);
        }
        LinearLayout words=TvStyle.column(activity);words.setGravity(Gravity.BOTTOM);
        String eyebrow=!e.kind.equals("live")&&progress.position(e)>1000?"WEITERSCHAUEN":favorites.contains(e.id)?"FAVORIT":history.stream().anyMatch(h->h.id.equals(e.id))?"ZULETZT GESEHEN":"LIVE TV";
        TextView eye=TvStyle.text(activity,eyebrow,12);eye.setLetterSpacing(.18f);eye.setTextColor(TvStyle.SECONDARY);eye.setTypeface(TvStyle.font(activity,R.font.geist_mono_regular));words.addView(eye);
        TextView headline=TvStyle.title(activity,lists.name(e),40);headline.setMaxLines(2);headline.setEllipsize(TextUtils.TruncateAt.END);LayoutParams hp=new LayoutParams(-1,-2);hp.topMargin=d(8);words.addView(headline,hp);
        TextView sub=TvStyle.text(activity,e.subtitle.isEmpty()?e.group:e.subtitle,16);sub.setTextColor(TvStyle.SECONDARY);sub.setMaxLines(1);sub.setEllipsize(TextUtils.TruncateAt.END);LayoutParams sp=new LayoutParams(-1,-2);sp.topMargin=d(8);words.addView(sub,sp);
        LinearLayout buttons=TvStyle.row(activity);LayoutParams bp=new LayoutParams(-1,d(44));bp.topMargin=d(18);words.addView(buttons,bp);
        Button play=TvStyle.button(activity,e.kind.equals("live")?"▶ Live ansehen":e.kind.equals("series")?"Episoden öffnen":progress.position(e)>1000?"▶ Fortsetzen":"▶ Abspielen",true,()->{if(e.kind.equals("series"))actions.open(e);else actions.play(e);});buttons.addView(play,new LayoutParams(-2,-1));
        Button favorite=TvStyle.button(activity,favorites.contains(e.id)?"★ Favorit":"☆ Zu Favoriten",()->actions.menu(e));favorite.setContentDescription("Favorit verwalten: "+lists.name(e));LayoutParams fp=new LayoutParams(-2,-1);fp.leftMargin=d(12);buttons.addView(favorite,fp);
        FrameLayout.LayoutParams wp=new FrameLayout.LayoutParams(d(540),-1,Gravity.LEFT|Gravity.BOTTOM);wp.setMargins(d(32),d(20),d(290),d(42));hero.addView(words,wp);
        if(heroItems.size()>1){Button next=TvStyle.button(activity,"›",()->{heroIndex=(heroIndex+1)%heroItems.size();render();});next.setContentDescription("Nächstes Titelbild");FrameLayout.LayoutParams np=new FrameLayout.LayoutParams(d(44),d(44),Gravity.RIGHT|Gravity.BOTTOM);np.setMargins(0,0,d(32),d(46));hero.addView(next,np);
            TextView dots=TvStyle.text(activity,(heroIndex+1)+" / "+heroItems.size(),12);dots.setTextColor(TvStyle.SECONDARY);FrameLayout.LayoutParams dp=new FrameLayout.LayoutParams(-2,-2,Gravity.CENTER_HORIZONTAL|Gravity.BOTTOM);dp.bottomMargin=d(12);hero.addView(dots,dp);}
        return hero;
    }
    /** Einstellungen als Kachelraster (3 Spalten); jede Kachel öffnet den bisherigen Bereich. */
    private View settingsPanel(){
        LinearLayout pane=TvStyle.column(activity);int side=Math.max(ox,d(32));pane.setPadding(side-d(16),d(8),side-d(16),d(24));
        Object[][] tiles={
            {"sources","Quellen","Zugang neu laden, wechseln oder entfernen",R.drawable.ic_tile_sources},
            {"lists","Meine Listen","Kategorien, Sender und Startseite ordnen",R.drawable.ic_tile_lists},
            {"lists:home","Darstellung","Kachelgrösse und Sendernamen",R.drawable.ic_tile_look},
            {"playback","Wiedergabe","Start, Kanal und Multiview",R.drawable.ic_tile_play},
            {"numbers","Kanalnummern","So wählst Du Sender per Zahl",R.drawable.ic_tile_numbers},
            {"info","Über IP Television+","Version, Funktionen und Hinweise",R.drawable.ic_tile_info}};
        for(int r=0;r<tiles.length;r+=3){
            LinearLayout line=TvStyle.row(activity);
            for(int c=0;c<3;c++){Object[] t=tiles[r+c];LayoutParams lp=new LayoutParams(0,Math.round(TvStyle.px(activity,120)),1);lp.setMargins(d(8),d(8),d(8),d(8));line.addView(settingsTile((String)t[0],(String)t[1],(String)t[2],(Integer)t[3]),lp);}
            pane.addView(line,new LayoutParams(-1,-2));
        }
        TextView note=TvStyle.text(activity,"IP Television+ · Google TV · "+BuildConfig.VERSION_NAME+"\nKeine Inhalte · Keine Werbung · Keine Analyse",14);note.setTextColor(TvStyle.SECONDARY);note.setPadding(d(8),d(20),0,d(12));pane.addView(note);
        LinearLayout.LayoutParams ap=new LinearLayout.LayoutParams(-2,-2);ap.leftMargin=d(8);pane.addView(TvStyle.arjoLine(activity),ap);
        return pane;
    }
    private View settingsTile(String key,String title,String subtitle,int icon){
        LinearLayout tile=TvStyle.row(activity);tile.setGravity(Gravity.CENTER_VERTICAL);tile.setPadding(d(20),d(16),d(20),d(16));
        int circle=Math.round(TvStyle.px(activity,64));ImageView image=new ImageView(activity);image.setImageResource(icon);int pad=Math.round(TvStyle.px(activity,18));image.setPadding(pad,pad,pad,pad);
        GradientDrawable round=new GradientDrawable();round.setShape(GradientDrawable.OVAL);round.setColor(TvStyle.RAISED);image.setBackground(round);image.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        tile.addView(image,new LayoutParams(circle,circle));
        LinearLayout words=TvStyle.column(activity);LayoutParams wp=new LayoutParams(0,-2,1);wp.leftMargin=d(16);wp.rightMargin=d(8);tile.addView(words,wp);
        TextView name=TvStyle.title(activity,title,20);name.setMaxLines(1);name.setEllipsize(TextUtils.TruncateAt.END);words.addView(name);
        TextView sub=TvStyle.text(activity,subtitle,14);sub.setTextColor(TvStyle.TEXT2);sub.setMaxLines(2);sub.setEllipsize(TextUtils.TruncateAt.END);LayoutParams sp=new LayoutParams(-1,-2);sp.topMargin=d(4);words.addView(sub,sp);
        TextView chevron=TvStyle.text(activity,"›",20);chevron.setTextColor(TvStyle.TEXT2);tile.addView(chevron);
        TvStyle.cardFocus(tile,null,TvStyle.GRAPHITE);tile.setContentDescription(title+", "+subtitle);tile.setOnClickListener(v->actions.action(key));
        return tile;
    }
    boolean hasDetail(){return detail!=null||detailView!=null;}
    /** Zeigt eine eigene Fläche (z. B. «Meine Listen») anstelle der Reihen; Zurück schliesst sie wie eine Detailseite. */
    void showPanel(View panel){closeDetail();detailView=panel;applyStage();stage.addView(panel,new FrameLayout.LayoutParams(-1,-1));}
    View panel(){return detail==null?detailView:null;}
    void closeDetail(){detail=null;detailPlot=null;episodeHost=null;seasons.clear();if(detailView!=null)stage.removeView(detailView);detailView=null;applyStage();focusMain();}
    void showDetail(Entry e){
        closeDetail();detail=e;applyStage();
        ScrollView scroll=new ScrollView(activity);scroll.setFillViewport(true);LinearLayout body=TvStyle.column(activity);body.setPadding(Math.max(ox,d(32)),d(20),Math.max(ox,d(32)),d(20)+oy);scroll.addView(body);detailView=scroll;stage.addView(scroll,new FrameLayout.LayoutParams(-1,-1));
        Button back=TvStyle.button(activity,"‹ Zurück",()->actions.action("back"));LayoutParams backParams=new LayoutParams(-2,d(40));backParams.bottomMargin=d(20);body.addView(back,backParams);
        LinearLayout header=TvStyle.row(activity);body.addView(header);
        ImageView poster=new ImageView(activity);poster.setBackground(TvStyle.shapePx(TvStyle.GRAPHITE,Color.TRANSPARENT,TvStyle.radiusPx(activity,TvStyle.R_CARD),0));poster.setClipToOutline(true);artwork.load(poster,e.image,false);header.addView(poster,new LayoutParams(d(150),d(225)));
        LinearLayout info=TvStyle.column(activity);LayoutParams ip=new LayoutParams(0,-2,1);ip.leftMargin=d(28);header.addView(info,ip);
        TextView name=TvStyle.title(activity,e.name,30);name.setMaxLines(3);info.addView(name);TextView meta=TvStyle.text(activity,e.subtitle.isEmpty()?e.group:e.subtitle,16);meta.setTextColor(TvStyle.SECONDARY);meta.setPadding(0,d(12),0,d(18));info.addView(meta);
        if(!e.kind.equals("series")){
            Button play=TvStyle.button(activity,progress.position(e)>1000?"▶ Fortsetzen":"▶ Abspielen",true,()->actions.play(e));info.addView(play,new LayoutParams(-2,d(46)));play.requestFocus();
        }else back.requestFocus();
        Button fav=TvStyle.button(activity,favorites.contains(e.id)?"★ Favorit verwalten":"☆ Zu Favoriten",()->actions.menu(e));LayoutParams f=new LayoutParams(-2,d(42));f.topMargin=d(12);info.addView(fav,f);
        detailPlot=TvStyle.text(activity,e.kind.equals("episode")?e.group:"Details werden geladen …",16);detailPlot.setTextColor(TvStyle.SECONDARY);detailPlot.setPadding(0,d(16),0,0);info.addView(detailPlot);
        episodeHost=TvStyle.column(activity);body.addView(episodeHost);
    }
    void detailInfo(Entry e,JSONObject response){
        if(detail==null||!detail.id.equals(e.id)||detailPlot==null)return;
        JSONObject info=response.optJSONObject("info");if(info==null){detailPlot.setText("Keine weiteren Angaben des Anbieters.");return;}
        List<String> parts=new ArrayList<>();for(String key:new String[]{"genre","plot","cast","director"}){String value=info.optString(key);if(!value.isEmpty()&&!value.equals("null"))parts.add((key.equals("cast")?"Besetzung: ":key.equals("director")?"Regie: ":"")+value);}
        detailPlot.setText(parts.isEmpty()?"Keine weiteren Angaben des Anbieters.":String.join("\n\n",parts));
    }
    void detailError(Entry e){if(detail!=null&&detail.id.equals(e.id)&&detailPlot!=null)detailPlot.setText("Details konnten nicht geladen werden. Die Wiedergabe bleibt verfügbar.");}
    void episodes(Entry e,List<Entry> list){
        if(detail==null||!detail.id.equals(e.id)||episodeHost==null)return;
        seasons.clear();for(Entry episode:list)seasons.computeIfAbsent(episode.group,k->new ArrayList<>()).add(episode);
        if(list.isEmpty()){episodeHost.addView(TvStyle.text(activity,"Keine Episoden verfügbar.",18));return;}
        selectedSeason=seasons.keySet().iterator().next();renderEpisodes();
    }
    private void renderEpisodes(){
        episodeHost.removeAllViews();Button select=TvStyle.button(activity,selectedSeason+" ⌄",()->{
            String[] names=seasons.keySet().toArray(new String[0]);new android.app.AlertDialog.Builder(activity).setTitle("Staffel wählen").setItems(names,(d,n)->{selectedSeason=names[n];renderEpisodes();}).setNegativeButton("Abbrechen",null).show();
        });LayoutParams p=new LayoutParams(-2,d(44));p.setMargins(0,d(24),0,d(14));episodeHost.addView(select,p);
        List<Entry> list=seasons.get(selectedSeason);int index=0;
        for(Entry episode:list){
            LinearLayout row=TvStyle.row(activity);row.setGravity(Gravity.CENTER_VERTICAL);TvStyle.pad(activity,row,16,14);
            TextView number=TvStyle.text(activity,String.valueOf(++index),20);number.setTextColor(TvStyle.SECONDARY);row.addView(number,new LayoutParams(d(44),-2));
            LinearLayout words=TvStyle.column(activity);words.addView(TvStyle.title(activity,episode.name,17));long resume=progress.position(episode);TextView sub=TvStyle.text(activity,resume>1000?"Fortsetzen ab "+(resume/60000)+" Min.":episode.subtitle,13);sub.setTextColor(TvStyle.SECONDARY);words.addView(sub);row.addView(words,new LayoutParams(0,-2,1));
            TextView play=TvStyle.text(activity,"▶",20);row.addView(play);TvStyle.cardFocus(row,null);row.setContentDescription(episode.name);row.setOnClickListener(v->actions.play(episode));row.setOnLongClickListener(v->{actions.menu(episode);return true;});LayoutParams rp=new LayoutParams(-1,-2);rp.bottomMargin=d(10);episodeHost.addView(row,rp);
        }
    }
}
