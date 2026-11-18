package ch.arjo.tv.android;

import android.app.*;
import android.content.*;
import android.os.Bundle;
import android.text.InputType;
import android.view.*;
import android.widget.*;
import java.util.*;
import java.util.concurrent.*;
import org.json.JSONObject;

@androidx.media3.common.util.UnstableApi
public final class MainActivity extends Activity {
    private final ExecutorService worker=Executors.newFixedThreadPool(2);
    private final Map<String,List<Entry>> cache=new HashMap<>();
    private CatalogCache diskCache;
    private int generation;
    private Source source,previousSource;
    private Vault vault;
    private Artwork artwork;
    private String kind="home",loginMode="xtream";
    private LibraryView library;
    private SharedPreferences state,progress;
    private Set<String> favorites=new HashSet<>();
    private Lists lists;
    private List<Entry> current=new ArrayList<>(),history=new ArrayList<>();
    @Override public void onCreate(Bundle saved){
        super.onCreate(saved);androidx.media3.common.util.Log.setLogLevel(androidx.media3.common.util.Log.LOG_LEVEL_OFF);TvStyle.fullscreen(this);
        vault=new Vault(this);diskCache=new CatalogCache(this,vault::cacheKey);artwork=new Artwork();state=getSharedPreferences("library",0);progress=getSharedPreferences("progress",0);
        FrameLayout waiting=new FrameLayout(this);waiting.setBackgroundColor(TvStyle.BLACK);ProgressBar spinner=new ProgressBar(this);waiting.addView(spinner,new FrameLayout.LayoutParams(d(36),d(36),Gravity.CENTER));setContentView(waiting);
        worker.execute(()->{
            Source restored=null;List<Entry> recent=new ArrayList<>();boolean failed=false;
            try{
                restored=vault.load();
                Source selected=PresetSource.choose(restored,BuildConfig.DEFAULT_PLAYLIST_URL,state.getString("appliedPreset",""));
                if(selected!=restored){vault.save(selected);state.edit().putString("appliedPreset",selected.scope()).commit();}
                restored=selected;if(restored!=null)recent=vault.history(restored.scope());
            }catch(Exception e){failed=true;}
            Source result=restored;List<Entry> restoredHistory=recent;boolean failure=failed;
            runOnUiThread(()->{if(isDestroyed()||isFinishing())return;if(result==null)login(failure?"Gespeicherter Zugang nicht lesbar. Bitte erneut anmelden.":"");else{source=result;history=restoredHistory;readFavorites();showLibrary();load();}});
        });
    }
    private int d(int n){return TvStyle.dp(this,n);}
    private EditText field(LinearLayout parent,String hint,boolean secret){
        EditText edit=new EditText(this);edit.setHint(hint);edit.setTextColor(TvStyle.WHITE);edit.setHintTextColor(TvStyle.SECONDARY);edit.setTextSize(16);edit.setSingleLine(true);edit.setSelectAllOnFocus(true);
        edit.setInputType(secret?InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_PASSWORD:InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS);
        edit.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS);edit.setSaveEnabled(false);edit.setId(View.generateViewId());
        edit.setBackground(TvStyle.inputBackground(this));TvStyle.pad(this,edit,14,10);
        LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,d(Math.max(46,Math.round(16*getResources().getConfiguration().fontScale*1.4f+20))));p.bottomMargin=d(10);parent.addView(edit,p);return edit;
    }
    private void login(String message){
        generation++;library=null;
        FrameLayout root=new FrameLayout(this);root.setBackgroundColor(TvStyle.BLACK);setContentView(root);
        ScrollView scroll=new ScrollView(this);scroll.setFillViewport(true);root.addView(scroll,new FrameLayout.LayoutParams(-1,-1));
        LinearLayout center=TvStyle.column(this);center.setGravity(Gravity.CENTER);TvStyle.pad(this,center,32,24);scroll.addView(center,new ScrollView.LayoutParams(-1,-1));
        LinearLayout form=TvStyle.column(this);int width=Math.min(560,Math.round(getResources().getDisplayMetrics().widthPixels/getResources().getDisplayMetrics().density)-64);center.addView(form,new LinearLayout.LayoutParams(d(width),-2));
        TextView mark=TvStyle.wordmark(this,64);LinearLayout.LayoutParams mp=new LinearLayout.LayoutParams(-2,-2);mp.gravity=Gravity.CENTER_HORIZONTAL;mp.bottomMargin=d(20);form.addView(mark,mp);
        LinearLayout modes=TvStyle.row(this);modes.setBackground(TvStyle.shape(TvStyle.RAISED,TvStyle.DIVIDER,24));TvStyle.pad(this,modes,3,3);LinearLayout.LayoutParams modesParams=new LinearLayout.LayoutParams(-1,d(44));modesParams.bottomMargin=d(14);form.addView(modes,modesParams);
        Button xtream=TvStyle.button(this,"Xtream",()->{loginMode="xtream";login("");});Button m3u=TvStyle.button(this,"M3U-Playlist",()->{loginMode="m3u";login("");});xtream.setSelected(loginMode.equals("xtream"));m3u.setSelected(loginMode.equals("m3u"));modes.addView(xtream,new LinearLayout.LayoutParams(0,-1,1));modes.addView(m3u,new LinearLayout.LayoutParams(0,-1,1));
        TextView note=TvStyle.text(this,loginMode.equals("xtream")?"Mit Xtream-Zugangsdaten anmelden":"Adresse Deiner M3U-Playlist",15);note.setGravity(Gravity.CENTER);note.setTextColor(TvStyle.SECONDARY);LinearLayout.LayoutParams np=new LinearLayout.LayoutParams(-1,-2);np.bottomMargin=d(14);form.addView(note,np);
        EditText address=field(form,loginMode.equals("xtream")?"Server (z. B. https://anbieter.example:8080)":"Playlist-Adresse (https://…)",false);address.setInputType(InputType.TYPE_CLASS_TEXT|InputType.TYPE_TEXT_VARIATION_URI);
        EditText user=loginMode.equals("xtream")?field(form,"Benutzername",false):null,password=loginMode.equals("xtream")?field(form,"Passwort",true):null;
        TextView error=TvStyle.text(this,message,14);error.setTextColor(TvStyle.SECONDARY);error.setGravity(Gravity.CENTER);error.setVisibility(message.isEmpty()?View.GONE:View.VISIBLE);form.addView(error);
        Button connect=TvStyle.button(this,"Anmelden",true,()->{});connect.setOnClickListener(v->{
            Source candidate;try{candidate=new Source(loginMode,address.getText().toString(),user==null?"":user.getText().toString(),password==null?"":password.getText().toString());}
            catch(Exception e){error.setText("Bitte HTTP-/HTTPS-Adresse und Zugang vollständig prüfen.");error.setVisibility(View.VISIBLE);return;}
            connect.setEnabled(false);error.setText("Quelle wird geprüft …");error.setVisibility(View.VISIBLE);int ticket=++generation;
            worker.execute(()->{
                try{
                    Catalog catalog=new Catalog(candidate);catalog.authenticate();List<Entry> list=catalog.load("live");NumberStore.apply(state,candidate.scope(),list,true);if(list.isEmpty()&&candidate.mode.equals("m3u"))throw new Exception();saveLater(candidate.scope(),candidate.mode.equals("xtream")?"live":"playlist",list);
                    List<Entry> candidateHistory;try{candidateHistory=vault.history(candidate.scope());}catch(Exception e){candidateHistory=new ArrayList<>();}List<Entry> recent=candidateHistory;
                    runOnUiThread(()->{
                        if(ticket!=generation||isDestroyed()||isFinishing())return;
                        try{vault.save(candidate);}catch(Exception e){connect.setEnabled(true);error.setText("Der Zugang konnte nicht sicher gespeichert werden. Bitte erneut versuchen.");return;}
                        source=candidate;previousSource=null;cache.clear();cache.put(candidate.mode.equals("xtream")?"live":"playlist",list);kind="home";history=recent;readFavorites();showLibrary();load();
                    });
                }catch(Exception e){runOnUiThread(()->{if(ticket==generation&&!isDestroyed()){connect.setEnabled(true);error.setText("Verbindung fehlgeschlagen. Adresse, Zugang und Netzwerk prüfen.");connect.requestFocus();}});}
            });
        });
        LinearLayout.LayoutParams cp=new LinearLayout.LayoutParams(-1,d(46));cp.topMargin=d(6);form.addView(connect,cp);
        if(previousSource!=null){Button cancel=TvStyle.button(this,"Abbrechen",()->{generation++;source=previousSource;previousSource=null;showLibrary();load();});LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(-1,d(42));p.topMargin=d(10);form.addView(cancel,p);}
        TextView privacy=TvStyle.text(this,"Nur Player · Keine Inhalte enthalten · Zugang lokal verschlüsselt",12);privacy.setTextColor(TvStyle.SECONDARY);privacy.setGravity(Gravity.CENTER);privacy.setPadding(0,d(16),0,0);form.addView(privacy);address.requestFocus();
    }
    private void readFavorites(){favorites=new HashSet<>(state.getStringSet("favorites:"+source.scope(),Collections.emptySet()));lists=new Lists(state,source.scope());if(library!=null)library.setLists(lists);}
    private void toggleFavorite(Entry e){if(!favorites.remove(e.id))favorites.add(e.id);state.edit().putStringSet("favorites:"+source.scope(),new HashSet<>(favorites)).apply();}
    private String progressKey(Entry e){return Source.hash(source.scope()+"|"+e.id);}
    private long position(Entry e){return progress.getLong(progressKey(e),0);}
    private float fraction(Entry e){long duration=progress.getLong(progressKey(e)+":duration",0);return duration>0?Math.min(.999f,(float)position(e)/duration):0;}
    private void showLibrary(){
        library=new LibraryView(this,artwork,new LibraryView.Actions(){
            public void navigate(String next){generation++;kind=next;library.activate(kind);load();}
            public void open(Entry e){MainActivity.this.open(e);}
            public void play(Entry e){MainActivity.this.play(e);}
            public void menu(Entry e){MainActivity.this.menu(e);}
            public void search(String query){if(library!=null)library.filter(query);}
            public void action(String action){MainActivity.this.action(action);}
        },new LibraryView.Progress(){public long position(Entry e){return MainActivity.this.position(e);}public float fraction(Entry e){return MainActivity.this.fraction(e);}});
        if(lists!=null)library.setLists(lists);setContentView(library);library.activate(kind);library.initialFocus();
    }
    private void load(){
        if(source==null||library==null)return;int ticket=++generation;String loadingKind=kind;Source loadingSource=source;
        library.setStatus("Inhalte werden geladen …");if(kind.equals("settings")){library.setStatus("IP Television+ · Deine Quellen bleiben auf diesem Gerät.");library.setData(current,favorites,history);return;}
        // Nach der Anmeldung liegt die Senderliste schon im Speicher: sofort starten statt auf Filme und Serien zu warten.
        if(!autoStarted&&(cache.containsKey("live")||cache.containsKey("playlist"))){current=entriesFor(kind);library.setData(current,favorites,history);maybeAutoStart();}
        Map<String,List<Entry>> existing=new HashMap<>(cache);
        worker.execute(()->{
            Map<String,List<Entry>> updated=new HashMap<>(existing);boolean failed=false;Set<String> stale=new HashSet<>();
            try{
                Catalog catalog=new Catalog(loadingSource);
                if(loadingSource.mode.equals("m3u")){if(!updated.containsKey("playlist")){updated.put("playlist",obtain(loadingSource,"playlist","live",catalog,stale));startEarly(ticket,"playlist",updated.get("playlist"));}}
                else{
                    boolean all=loadingKind.equals("home")||loadingKind.equals("search")||loadingKind.equals("favorites");
                    for(String k:all?new String[]{"live","movie","series"}:new String[]{loadingKind})if(!updated.containsKey(k)){
                        try{updated.put(k,obtain(loadingSource,k,k,catalog,stale));if(k.equals("live"))startEarly(ticket,k,updated.get(k));}catch(Exception e){failed=true;}
                    }
                }
            }catch(Exception e){failed=true;}
            boolean partial=failed;
            // Kontostatus nur beim ersten Laden und nach «Aktualisieren» prüfen, nicht bei jedem Tabwechsel.
            boolean check=existing.isEmpty();long expiry=0;String problem=null;
            if(check){
                try{expiry=new Catalog(loadingSource).authenticate();}catch(Exception e){problem=e.getMessage()==null?"Anbieter nicht erreichbar.":e.getMessage();}
                if(problem==null&&failed)problem="Einige Inhalte konnten nicht geladen werden.";
            }
            long healthExpiry=expiry;String healthProblem=problem;
            runOnUiThread(()->{
                if(ticket!=generation||isDestroyed()||isFinishing()||library==null)return;if(check)library.setHealth(healthProblem==null?1:-1,healthProblem,healthExpiry);cache.clear();cache.putAll(updated);current=entriesFor(loadingKind);
                library.setData(current,favorites,history);maybeAutoStart();library.setStatus(partial?"Einige Inhalte konnten nicht geladen werden. Unter Einstellungen erneut laden.":current.size()+" Inhalte · OK: öffnen · OK halten: Favoriten");
                if(!stale.isEmpty())refreshInBackground(loadingSource,stale);
            });
        });
    }
    /**
     * Fernsehen zuerst: Sobald die Senderliste da ist (meist aus dem Zwischenspeicher), läuft der Autostart sofort.
     * Filme und Serien laden danach weiter und warten nicht mehr vor dem ersten Bild.
     */
    private void startEarly(int ticket,String key,List<Entry> live){
        if(autoStarted||live==null||live.isEmpty())return;List<Entry> copy=new ArrayList<>(live);
        runOnUiThread(()->{
            if(ticket!=generation||autoStarted||isDestroyed()||isFinishing()||library==null)return;
            cache.put(key,copy);current=entriesFor(kind);library.setData(current,favorites,history);maybeAutoStart();
        });
    }
    /** Katalogteil aus dem lokalen Zwischenspeicher, sonst aus dem Netz (und dann gespeichert). Alte Stände werden in `stale` gemerkt. */
    private List<Entry> obtain(Source s,String key,String apiKind,Catalog catalog,Set<String> stale) throws Exception{
        CatalogCache.Hit hit=diskCache.load(s.scope(),key);
        if(hit!=null){if(apiKind.equals("live"))NumberStore.apply(state,s.scope(),hit.entries,true);if(hit.stale())stale.add(key);return hit.entries;}
        List<Entry> loaded=catalog.load(apiKind);if(apiKind.equals("live"))NumberStore.apply(state,s.scope(),loaded,true);
        if(!loaded.isEmpty())saveLater(s.scope(),key,loaded);return loaded;
    }
    /** Speichert im Hintergrund, damit die Anzeige nicht darauf wartet. */
    private void saveLater(String scope,String key,List<Entry> entries){worker.execute(()->diskCache.save(scope,key,new ArrayList<>(entries)));}
    /** Lädt veraltete Teile still nach und speichert sie. Die Ansicht bleibt unverändert (kein Fokussprung); neu zeigt es der nächste Tabwechsel oder Start. */
    private void refreshInBackground(Source s,Set<String> keys){
        Set<String> todo=new HashSet<>(keys);
        worker.execute(()->{
            Map<String,List<Entry>> fresh=new HashMap<>();
            try{Catalog catalog=new Catalog(s);for(String key:todo){String api=key.equals("playlist")?"live":key;List<Entry> loaded=catalog.load(api);if(api.equals("live"))NumberStore.apply(state,s.scope(),loaded,true);if(!loaded.isEmpty()){diskCache.save(s.scope(),key,loaded);fresh.put(key,loaded);}}}
            catch(Exception e){return;}
            runOnUiThread(()->{if(isDestroyed()||isFinishing()||source!=s)return;cache.putAll(fresh);});
        });
    }
    /** Alle geladenen Einträge, auch die in «Meine Listen» ausgeblendeten. */
    private List<Entry> allEntries(){List<Entry> all=new ArrayList<>();if(source.mode.equals("m3u"))all.addAll(cache.getOrDefault("playlist",Collections.emptyList()));else for(String k:new String[]{"live","movie","series"})all.addAll(cache.getOrDefault(k,Collections.emptyList()));return all;}
    private List<Entry> entriesFor(String screen){
        List<Entry> all=lists==null?allEntries():lists.visible(allEntries());
        List<Entry> out=new ArrayList<>();for(Entry e:all)if(screen.equals("home")||screen.equals("search")||screen.equals("settings")||screen.equals("favorites")? !screen.equals("favorites")||favorites.contains(e.id):screen.equals("series")?e.kind.equals("series")||e.kind.equals("episode"):e.kind.equals(screen))out.add(e);return out;
    }
    private void open(Entry e){
        if(e.kind.equals("live")){play(e);return;}library.showDetail(e);int ticket=++generation;if(source.mode.equals("m3u")||e.kind.equals("episode")){library.detailInfo(e,new JSONObject());return;}
        Source loadingSource=source;worker.execute(()->{
            try{Catalog c=new Catalog(loadingSource);JSONObject details=c.detail(e);List<Entry> episodes=e.kind.equals("series")?c.episodes(details):Collections.emptyList();
                runOnUiThread(()->{if(ticket!=generation||isDestroyed()||library==null)return;library.detailInfo(e,details);if(e.kind.equals("series"))library.episodes(e,episodes);});
            }catch(Exception error){runOnUiThread(()->{if(ticket==generation&&!isDestroyed()&&library!=null)library.detailError(e);});}
        });
    }
    private Entry resolved(Entry e){
        if(!source.mode.equals("xtream")||e.kind.equals("series"))return e;
        try{String id=e.id.substring(e.id.indexOf(':')+1);String path=java.net.URI.create(e.url).getPath();String ext=path.substring(path.lastIndexOf('.')+1);
            return new Entry(e.id,e.name,e.group,source.stream(e.kind.equals("episode")?"series":e.kind.equals("movie")?"movie":"live",id,ext),e.kind,e.image,e.subtitle);
        }catch(Exception ignored){return e;}
    }
    private void play(Entry entry){
        Entry e=resolved(entry);if(!Source.isWeb(e.url))return;
        remember(e);
        Intent intent=new Intent(this,PlayerActivity.class);intent.putExtra("url",e.url);intent.putExtra("name",e.name);intent.putExtra("live",e.kind.equals("live"));intent.putExtra("key",progressKey(e));
        intent.putExtra("entryId",e.id);intent.putExtra("group",e.group);intent.putExtra("scope",source.scope());
        if(e.kind.equals("live"))intent.putExtra("queueToken",PlaybackQueue.register(new PlaybackQueue(entriesFor("live"),e,source.scope(),liveGroupOrder())));
        startActivityForResult(intent,100);
    }
    /** Gruppen der sichtbaren Live-Sender in eigener Reihenfolge (Meine Listen). */
    private List<String> liveGroupOrder(){Set<String> groups=new LinkedHashSet<>();for(Entry e:entriesFor("live"))groups.add(e.group);return lists==null?new ArrayList<>(groups):lists.ordered("live",groups);}
    private boolean autoStarted;
    /** Fernsehen zuerst: nach dem Laden läuft Kanal 1 (kleinste Nummer) oder, wenn gewählt, der zuletzt gesehene Sender. */
    private void maybeAutoStart(){
        if(autoStarted||source==null||isFinishing()||isDestroyed())return;
        Entry start=tvEntry(state.getBoolean("startLast",false));
        if(start==null)return;
        autoStarted=true;play(start);
    }
    private Entry tvEntry(boolean preferLast){
        List<Entry> live=entriesFor("live");if(live.isEmpty())return null;
        if(preferLast)for(Entry h:history)if(h.kind.equals("live"))for(Entry e:live)if(e.id.equals(h.id))return e;
        Entry first=null;for(Entry e:live)if(e.number>0&&(first==null||e.number<first.number))first=e;
        return first!=null?first:live.get(0);
    }
    private void remember(Entry e){
        history.removeIf(h->h.id.equals(e.id));history.add(0,e);if(history.size()>30)history=new ArrayList<>(history.subList(0,30));
        try{vault.saveHistory(source.scope(),history);}catch(Exception ignored){Toast.makeText(this,"Verlauf konnte nicht sicher gespeichert werden.",Toast.LENGTH_SHORT).show();}
    }
    @Override protected void onActivityResult(int request,int result,Intent data){
        super.onActivityResult(request,result,data);if(request==100&&source!=null&&!isFinishing())Toast.makeText(this,"Menü · Zurück: Fernsehen",Toast.LENGTH_SHORT).show();if(request!=100||result!=RESULT_OK||data==null||source==null)return;
        String id=data.getStringExtra("entryId");for(Entry e:entriesFor("live"))if(e.id.equals(id)){remember(e);break;}
    }
    private void menu(Entry entry){
        boolean favorite=favorites.contains(entry.id),live=entry.kind.equals("live");
        List<String> items=new ArrayList<>(Arrays.asList(entry.kind.equals("series")?"Episoden öffnen":live?"Abspielen":"Details öffnen",favorite?"Aus Favoriten entfernen":"Zu Favoriten hinzufügen"));
        if(live)items.addAll(Arrays.asList("Im Multiview ansehen","Ausblenden"));
        new AlertDialog.Builder(this).setTitle(lists.name(entry)).setItems(items.toArray(new String[0]),(dialog,index)->{
            if(index==0)open(entry);
            else if(index==1){toggleFavorite(entry);library.setData(current,favorites,history);}
            else if(index==2)multiview(entry);
            else{lists.setHidden(entry,true);current=entriesFor(kind);library.setData(current,favorites,history);Toast.makeText(this,"Ausgeblendet. Wieder einblenden unter Einstellungen › Meine Listen.",Toast.LENGTH_LONG).show();}
        }).setNegativeButton("Schliessen",null).show();
    }
    /** Öffnet das Multiview mit den sichtbaren Sendern (Adressen nur im Arbeitsspeicher). */
    private void multiview(Entry first){
        if(source==null)return;List<Entry> live=new ArrayList<>();for(Entry e:entriesFor("live")){Entry r=resolved(e);if(Source.isWeb(r.url))live.add(r);}
        if(live.isEmpty()){Toast.makeText(this,"Noch keine Sender geladen.",Toast.LENGTH_SHORT).show();return;}
        MultiviewActivity.prepare(live);Intent intent=new Intent(this,MultiviewActivity.class).putExtra("scope",source.scope());if(first!=null)intent.putExtra("entryId",first.id);startActivity(intent);
    }
    private void editLists(String page){
        library.showPanel(new ListEditor(this,lists,page,new ListEditor.Host(){
            public List<Entry> all(){return allEntries();}
            public Set<String> favorites(){return favorites;}
            public void toggleFavorite(Entry e){MainActivity.this.toggleFavorite(e);}
            public void changed(){current=entriesFor(kind);library.setData(current,favorites,history);}
            public void close(){library.closeDetail();}
        }));
    }
    private void action(String action){
        if(action.equals("back")){onBackPressed();return;}
        if(action.equals("lists")){editLists(kind.equals("live")?"channels":"categories");return;}
        if(action.equals("lists:home")){editLists("home");return;}
        if(action.equals("sources")){sheet("Quellen",new String[]{"Quelle neu laden","Anderen Zugang verwenden","Gespeicherten Zugang entfernen"},new String[]{"reload","source","forget"});return;}
        if(action.equals("playback")){
            boolean last=state.getBoolean("startLast",false);
            sheet("Wiedergabe",new String[]{last?"Beim Start: zuletzt gesehener Kanal":"Beim Start: Kanal 1","Multiview öffnen"},new String[]{"startmode","multiview"});return;
        }
        if(action.equals("numbers")){new AlertDialog.Builder(this).setTitle("Kanalnummern").setMessage("Jeder Sender hat eine feste Nummer. Im Fernsehen gibst Du sie mit den Zifferntasten ein. OK halten öffnet den Nummernblock.").setPositiveButton("Schliessen",null).show();return;}
        if(action.equals("multiview")){multiview(null);return;}
        if(action.equals("startmode")){boolean last=!state.getBoolean("startLast",false);state.edit().putBoolean("startLast",last).apply();Toast.makeText(this,last?"Beim Start: zuletzt gesehener Kanal":"Beim Start: Kanal 1",Toast.LENGTH_SHORT).show();return;}
        if(action.equals("reload")){cache.clear();diskCache.clear();if(kind.equals("settings")){kind="home";library.activate(kind);}load();return;}
        if(action.equals("source")){previousSource=source;login("");return;}
        if(action.equals("forget"))new AlertDialog.Builder(this).setMessage("Gespeicherten Zugang und Verlauf von diesem Fernseher entfernen?").setPositiveButton("Entfernen",(dialog,n)->{generation++;vault.forget();diskCache.clear();source=null;previousSource=null;cache.clear();history.clear();login("");}).setNegativeButton("Abbrechen",null).show();
        if(action.equals("info")){
            LinearLayout box=TvStyle.column(this);box.setPadding(d(24),d(8),d(24),d(8));
            TextView message=new TextView(this);message.setText("Design der Apple-Version mit Logo-Kacheln, grosser Startseite, Filmplakaten und Detailansichten; für Fernbedienung angepasst.\n\nXtream/M3U, Live TV, Filme, Serien/Episoden, Suche, Favoriten, Weiterschauen, Meine Listen (Ausblenden, Umbenennen, Reihenfolge, Aufbau der Startseite) und Multiview mit bis zu vier Sendern.\n\nNoch nicht enthalten: EPG, Catch-up, Kindersicherung, iCloud-Sync und VLC-Fallback. Codec-Unterstützung hängt vom Fernseher ab.\n\nKeine Inhalte, Werbung oder Analyse. Bilder und Streams kommen von Deiner Quelle. HTTPS nach Möglichkeit verwenden.");
            message.setTextColor(TvStyle.SECONDARY);message.setTextSize(15);box.addView(message);
            LinearLayout.LayoutParams lp=new LinearLayout.LayoutParams(-2,-2);lp.topMargin=d(18);box.addView(TvStyle.arjoLine(this),lp);
            ScrollView scroll=new ScrollView(this);scroll.addView(box);
            new AlertDialog.Builder(this).setTitle("IP Television+ · Google TV · "+BuildConfig.VERSION_NAME).setView(scroll).setPositiveButton("Schliessen",null).setNeutralButton("Nach Updates suchen",(dialog,n)->checkUpdate(true)).show();
        }
    }
    /** Prüft GitHub auf eine neuere Version; manuell mit Rückmeldung, automatisch höchstens einmal pro Tag und still. */
    private void checkUpdate(boolean manual){
        if(!manual&&!Updater.due(this))return;
        Updater.check(this,(info,error)->{
            if(isFinishing())return;
            if(error!=null){if(manual)Toast.makeText(this,"Update-Prüfung fehlgeschlagen: "+error,Toast.LENGTH_LONG).show();return;}
            if(info==null){if(manual)Toast.makeText(this,"Du hast die neueste Version ("+BuildConfig.VERSION_NAME+").",Toast.LENGTH_SHORT).show();return;}
            new AlertDialog.Builder(this).setTitle("Update verfügbar: "+info.version).setMessage(info.notes.isEmpty()?"Eine neue Version liegt auf GitHub bereit.":info.notes)
                .setPositiveButton("Installieren",(dialog,n)->{Toast.makeText(this,"Update wird geladen …",Toast.LENGTH_SHORT).show();Updater.install(this,info,(i,e)->{if(e!=null)Toast.makeText(this,"Update fehlgeschlagen: "+e,Toast.LENGTH_LONG).show();});})
                .setNegativeButton("Später",null).show();
        });
    }
    /** Auswahlblatt: jeder Eintrag führt die bisherige Aktion mit dem gleichen Schlüssel aus. */
    private void sheet(String title,String[] labels,String[] keys){
        new AlertDialog.Builder(this).setTitle(title).setItems(labels,(dialog,n)->action(keys[n])).setNegativeButton("Schliessen",null).show();
    }
    @Override protected void onResume(){super.onResume();checkUpdate(false);if(library!=null&&source!=null)library.setData(current,favorites,history);}
    @Override public void onBackPressed(){
        if(library!=null&&library.hasDetail()){generation++;library.closeDetail();return;}
        if(previousSource!=null){generation++;source=previousSource;previousSource=null;showLibrary();load();return;}
        if(library!=null&&!kind.equals("home")){kind="home";library.activate(kind);load();return;}
        Entry tv=source==null?null:tvEntry(true);if(tv!=null){autoStarted=true;play(tv);return;}
        new AlertDialog.Builder(this).setMessage("IP Television+ beenden?").setPositiveButton("Beenden",(dialog,n)->finish()).setNegativeButton("Bleiben",null).show();
    }
    @Override protected void onDestroy(){generation++;worker.shutdownNow();if(artwork!=null)artwork.close();super.onDestroy();}
}
