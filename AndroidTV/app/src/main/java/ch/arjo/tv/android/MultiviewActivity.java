package ch.arjo.tv.android;

import android.app.*;
import android.content.*;
import android.graphics.drawable.*;
import android.os.*;
import android.text.*;
import android.view.*;
import android.widget.*;
import androidx.media3.common.*;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.*;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.ui.*;
import androidx.recyclerview.widget.*;
import java.util.*;

/** Bis zu vier Sender gleichzeitig. Nur ein Bild hat Ton, die anderen laufen stumm und mit begrenzter Bitrate. */
@androidx.media3.common.util.UnstableApi
public final class MultiviewActivity extends Activity {
    static final int MAX=4;
    static final int BACKGROUND_BITRATE=2_500_000;
    // Senderliste nur im Arbeitsspeicher (wie PlaybackQueue), nie in einem grossen Intent.
    private static List<Entry> catalog=new ArrayList<>();
    static synchronized void prepare(List<Entry> live){catalog=new ArrayList<>(live);}
    private static synchronized List<Entry> catalog(){return new ArrayList<>(catalog);}

    private final class Slot { Entry entry; ExoPlayer player; PlayerView video; FrameLayout tile; TextView label; }
    private final List<Slot> slots=new ArrayList<>();
    private final Handler main=new Handler(Looper.getMainLooper());
    private final Runnable hide=()->setControls(false);
    private FrameLayout root,grid;
    private LinearLayout bar,empty;
    private View picker;
    private TextView count;
    private Button add,arrange;
    private Slot audio;
    private String layout,scope;
    private Lists lists;
    private Artwork artwork;
    private SharedPreferences state;
    private Set<String> favorites=new HashSet<>();
    private boolean started;

    @Override public void onCreate(Bundle saved){
        super.onCreate(saved);androidx.media3.common.util.Log.setLogLevel(androidx.media3.common.util.Log.LOG_LEVEL_OFF);TvStyle.fullscreen(this);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        state=getSharedPreferences("library",0);scope=getIntent().getStringExtra("scope");if(scope==null)scope="";
        lists=new Lists(state,scope);artwork=new Artwork();favorites=new HashSet<>(state.getStringSet("favorites:"+scope,Collections.emptySet()));layout=state.getString("multiview:layout","grid");
        root=new FrameLayout(this);root.setBackgroundColor(TvStyle.BLACK);setContentView(root);
        grid=new FrameLayout(this);grid.setClipChildren(false);root.addView(grid,new FrameLayout.LayoutParams(-1,-1));
        grid.addOnLayoutChangeListener((v,l,t,r,b,ol,ot,or,ob)->{if(r-l!=or-ol||b-t!=ob-ot)arrange();});
        buildBar();buildEmpty();
        String first=getIntent().getStringExtra("entryId");if(first!=null)for(Entry e:catalog())if(e.id.equals(first)){slots.add(slot(e));break;}
        if(!slots.isEmpty())audio=slots.get(0);
        refresh();
    }
    private int d(int n){return TvStyle.dp(this,n);}

    // Bedienleiste oben: Anzahl, Sender hinzufügen, Anordnung, Schliessen.
    private void buildBar(){
        bar=TvStyle.row(this);bar.setGravity(Gravity.CENTER_VERTICAL);bar.setBackground(TvStyle.shape(0xD0090A0A,0x40FDFDFC,48));TvStyle.pad(this,bar,16,8);
        LinearLayout words=TvStyle.column(this);TextView eye=TvStyle.text(this,"MULTIVIEW",12);eye.setLetterSpacing(.15f);eye.setTextColor(TvStyle.SECONDARY);eye.setTypeface(TvStyle.font(this,R.font.geist_mono_regular));words.addView(eye);
        count=TvStyle.title(this,"",14);words.addView(count);bar.addView(words,new LinearLayout.LayoutParams(0,-2,1));
        add=TvStyle.button(this,"+ Sender hinzufügen",true,()->pick(-1));bar.addView(add,params(-2));
        arrange=TvStyle.button(this,"",this::chooseLayout);bar.addView(arrange,params(-2));
        Button close=TvStyle.button(this,"Schliessen",this::finish);bar.addView(close,params(-2));
        FrameLayout.LayoutParams p=new FrameLayout.LayoutParams(-1,-2,Gravity.TOP);p.setMargins(d(32),d(18),d(32),0);root.addView(bar,p);
    }
    private LinearLayout.LayoutParams params(int width){LinearLayout.LayoutParams p=new LinearLayout.LayoutParams(width,d(40));p.leftMargin=d(10);return p;}
    private void buildEmpty(){
        empty=TvStyle.column(this);empty.setGravity(Gravity.CENTER);
        TextView title=TvStyle.title(this,"",36);title.setText("Mehrere Sender gleichzeitig");empty.addView(title);
        TextView note=TvStyle.text(this,"Bis zu vier Bilder. Nur eines hat Ton – wähle es mit OK.",16);note.setTextColor(TvStyle.SECONDARY);note.setPadding(0,d(12),0,d(24));empty.addView(note);
        empty.addView(TvStyle.button(this,"+ Sender wählen",true,()->pick(-1)),new LinearLayout.LayoutParams(-2,d(46)));
        root.addView(empty,new FrameLayout.LayoutParams(-1,-1));
    }

    private Slot slot(Entry e){
        Slot s=new Slot();s.entry=e;
        s.tile=new FrameLayout(this);s.tile.setFocusable(true);s.tile.setClickable(true);s.tile.setDefaultFocusHighlightEnabled(false);s.tile.setId(View.generateViewId());s.tile.setBackgroundColor(TvStyle.BLACK);s.tile.setClipToOutline(true);
        StateListDrawable ring=new StateListDrawable();ring.addState(new int[]{android.R.attr.state_focused},TvStyle.focusRing(this,4));ring.addState(new int[]{},new ColorDrawable(0));s.tile.setForeground(ring);
        s.video=new PlayerView(this);s.video.setUseController(false);s.video.setShowBuffering(PlayerView.SHOW_BUFFERING_ALWAYS);s.video.setResizeMode(AspectRatioFrameLayout.RESIZE_MODE_FIT);s.video.setFocusable(false);
        s.tile.addView(s.video,new FrameLayout.LayoutParams(-1,-1));
        s.label=TvStyle.title(this,"",14);s.label.setBackground(TvStyle.shape(0x99090A0A,0,40));TvStyle.pad(this,s.label,12,6);s.label.setMaxLines(1);s.label.setEllipsize(TextUtils.TruncateAt.END);
        FrameLayout.LayoutParams lp=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.LEFT);lp.setMargins(d(12),0,d(12),d(12));s.tile.addView(s.label,lp);
        s.tile.setOnClickListener(v->{setAudio(s);reveal();});
        s.tile.setOnLongClickListener(v->{menu(s);return true;});
        grid.addView(s.tile,new FrameLayout.LayoutParams(0,0));
        if(started)start(s);
        return s;
    }
    private void start(Slot s){
        DefaultHttpDataSource.Factory http=new DefaultHttpDataSource.Factory().setUserAgent("ARJOTV-Android/0.2").setConnectTimeoutMs(15000).setReadTimeoutMs(20000);
        s.player=new ExoPlayer.Builder(this).setRenderersFactory(new DefaultRenderersFactory(this).setEnableDecoderFallback(true)).setMediaSourceFactory(new DefaultMediaSourceFactory(this).setDataSourceFactory(http)).build();
        s.video.setPlayer(s.player);s.player.setMediaItem(MediaItem.fromUri(s.entry.url));s.player.prepare();s.player.setPlayWhenReady(true);
        s.player.addListener(new Player.Listener(){@Override public void onPlayerError(PlaybackException error){if(!isFinishing())s.label.setText(lists.name(s.entry)+" · nicht verfügbar");}});
    }
    private void stop(Slot s){if(s.player!=null){s.video.setPlayer(null);s.player.release();s.player=null;}}

    private void setAudio(Slot s){audio=s;refresh();}
    private void refresh(){
        for(Slot s:slots){
            boolean sound=s==audio;
            if(s.player!=null){s.player.setVolume(sound?1f:0f);
                s.player.setTrackSelectionParameters(s.player.getTrackSelectionParameters().buildUpon().setMaxVideoBitrate(sound||slots.size()==1?Integer.MAX_VALUE:BACKGROUND_BITRATE).build());}
            s.label.setText((sound?"🔊  ":"")+lists.name(s.entry));s.label.setTextColor(sound?TvStyle.WHITE:TvStyle.SECONDARY);
            s.tile.setContentDescription(lists.name(s.entry)+(sound?", Ton an":", stumm"));
        }
        count.setText(slots.size()+" von "+MAX+" Sendern");add.setEnabled(slots.size()<MAX);
        arrange.setText("Anordnung: "+MultiviewLayout.label(layout)+" ⌄");arrange.setEnabled(slots.size()>1);
        empty.setVisibility(slots.isEmpty()?View.VISIBLE:View.GONE);
        arrange();reveal();
    }
    /** Legt die Bilder nach der gewählten Anordnung über die ganze Fläche; nur so viele Felder wie laufende Sender. */
    private void arrange(){
        int w=grid.getWidth(),h=grid.getHeight();if(w==0||h==0)return;
        int focus=Math.max(0,slots.indexOf(audio));float[][] frames=MultiviewLayout.frames(layout,slots.size(),w,h,focus);
        boolean single=slots.size()==1,pip=MultiviewLayout.overlaps(layout);
        for(int i=0;i<slots.size();i++){
            Slot s=slots.get(i);float[] f=frames[i];boolean floating=pip&&i!=focus,full=single||(pip&&!floating);int gap=full?0:d(2);
            FrameLayout.LayoutParams p=new FrameLayout.LayoutParams(Math.round(f[2])-2*gap,Math.round(f[3])-2*gap);p.leftMargin=Math.round(f[0])+gap;p.topMargin=Math.round(f[1])+gap;s.tile.setLayoutParams(p);
            s.tile.setOutlineProvider(full?ViewOutlineProvider.BACKGROUND:new ViewOutlineProvider(){@Override public void getOutline(View v,android.graphics.Outline o){o.setRoundRect(0,0,v.getWidth(),v.getHeight(),d(10));}});
            s.tile.setElevation(floating?d(12):0);s.tile.setTranslationZ(floating?d(4):0);
        }
    }

    private void chooseLayout(){
        new AlertDialog.Builder(this).setTitle("Anordnung").setItems(MultiviewLayout.LABELS,(dialog,n)->{layout=MultiviewLayout.KEYS[n];state.edit().putString("multiview:layout",layout).apply();refresh();}).setNegativeButton("Abbrechen",null).show();
    }
    private void menu(Slot s){
        new AlertDialog.Builder(this).setTitle(lists.name(s.entry)).setItems(new String[]{"Ton hier","Anderen Sender wählen …","Entfernen"},(dialog,n)->{
            if(n==0)setAudio(s);else if(n==1)pick(slots.indexOf(s));else remove(s);
        }).setNegativeButton("Schliessen",null).show();
    }
    private void remove(Slot s){
        stop(s);grid.removeView(s.tile);slots.remove(s);if(audio==s)audio=slots.isEmpty()?null:slots.get(0);refresh();
        if(!slots.isEmpty())slots.get(0).tile.requestFocus();else empty.requestFocus();
    }
    private void choose(Entry e,int replace){
        closePicker();
        for(Slot s:slots)if(s.entry.id.equals(e.id)){toast("Dieser Sender läuft schon im Multiview.");return;}
        if(replace>=0&&replace<slots.size()){Slot s=slots.get(replace);stop(s);s.entry=e;if(started)start(s);refresh();s.tile.requestFocus();return;}
        if(slots.size()>=MAX){toast("Es sind höchstens "+MAX+" Bilder gleichzeitig möglich.");return;}
        Slot s=slot(e);slots.add(s);if(audio==null)audio=s;refresh();s.tile.requestFocus();
    }
    private void toast(String text){Toast.makeText(this,text,Toast.LENGTH_SHORT).show();}

    // Senderwahl: Quellen links (Favoriten, Kategorien), Logo-Raster rechts.
    private void pick(int replace){
        closePicker();List<Entry> all=lists.visible(catalog());
        LinkedHashMap<String,List<Entry>> groups=new LinkedHashMap<>();List<Entry> fav=new ArrayList<>();
        for(Entry e:all){if(favorites.contains(e.id))fav.add(e);groups.computeIfAbsent(e.group,k->new ArrayList<>()).add(e);}
        List<String> names=new ArrayList<>();List<List<Entry>> contents=new ArrayList<>();
        if(!fav.isEmpty()){names.add("★ Favoriten");contents.add(fav);}
        for(String g:lists.ordered("live",groups.keySet())){names.add(lists.groupName("live",g));contents.add(groups.get(g));}
        LinearLayout panel=TvStyle.row(this);panel.setBackgroundColor(0xF2090A0A);TvStyle.pad(this,panel,32,24);panel.setClickable(true);
        LinearLayout side=TvStyle.column(this);TextView heading=TvStyle.title(this,replace>=0?"Sender ersetzen":"Sender hinzufügen",24);heading.setPadding(0,0,0,d(14));side.addView(heading);
        ScrollView sideScroll=new ScrollView(this);LinearLayout sources=TvStyle.column(this);sideScroll.addView(sources);side.addView(sideScroll,new LinearLayout.LayoutParams(-1,0,1));
        panel.addView(side,new LinearLayout.LayoutParams(d(250),-1));
        RecyclerView tiles=new RecyclerView(this);tiles.setLayoutManager(new GridLayoutManager(this,4));tiles.setClipToPadding(false);tiles.setPadding(d(16),d(8),d(8),d(16));tiles.setItemAnimator(null);
        LinearLayout.LayoutParams tp=new LinearLayout.LayoutParams(0,-1,1);tp.leftMargin=d(16);panel.addView(tiles,tp);
        List<Button> buttons=new ArrayList<>();
        for(int i=0;i<names.size();i++){List<Entry> list=contents.get(i);Button b=TvStyle.button(this,names.get(i),()->{});b.setGravity(Gravity.LEFT|Gravity.CENTER_VERTICAL);b.setMaxLines(1);b.setEllipsize(TextUtils.TruncateAt.END);
            b.setOnClickListener(v->{for(Button o:buttons)o.setSelected(o==v);tiles.setAdapter(new PickAdapter(list,replace));tiles.post(()->{View first=tiles.getLayoutManager().findViewByPosition(0);if(first!=null)first.requestFocus();});});
            LinearLayout.LayoutParams bp=new LinearLayout.LayoutParams(-1,d(42));bp.bottomMargin=d(6);sources.addView(b,bp);buttons.add(b);}
        if(names.isEmpty())side.addView(TvStyle.text(this,"Keine Sender verfügbar.",16));
        else{buttons.get(0).setSelected(true);tiles.setAdapter(new PickAdapter(contents.get(0),replace));}
        picker=panel;root.addView(panel,new FrameLayout.LayoutParams(-1,-1));if(!buttons.isEmpty())buttons.get(0).requestFocus();
        main.removeCallbacks(hide);
    }
    private void closePicker(){if(picker!=null){root.removeView(picker);picker=null;reveal();}}
    private final class PickAdapter extends RecyclerView.Adapter<RecyclerView.ViewHolder> {
        final List<Entry> list;final int replace;
        PickAdapter(List<Entry> list,int replace){this.list=list;this.replace=replace;}
        @Override public int getItemCount(){return list.size();}
        @Override public RecyclerView.ViewHolder onCreateViewHolder(ViewGroup parent,int type){
            LinearLayout card=TvStyle.column(MultiviewActivity.this);TvStyle.pad(MultiviewActivity.this,card,6,6);RecyclerView.LayoutParams p=new RecyclerView.LayoutParams(-1,-2);p.setMargins(d(4),d(4),d(4),d(4));card.setLayoutParams(p);
            FrameLayout frame=new FrameLayout(MultiviewActivity.this);frame.setBackground(TvStyle.shapePx(TvStyle.RAISED,0x14FDFDFC,TvStyle.radiusPx(MultiviewActivity.this,TvStyle.R_CARD),1));TvStyle.pad(MultiviewActivity.this,frame,14,10);
            ImageView logo=new ImageView(MultiviewActivity.this);frame.addView(logo,new FrameLayout.LayoutParams(-1,-1));card.addView(frame,new LinearLayout.LayoutParams(-1,d(72)));
            TextView name=TvStyle.title(MultiviewActivity.this,"",14);name.setMaxLines(1);name.setEllipsize(TextUtils.TruncateAt.END);name.setPadding(0,d(6),0,0);card.addView(name);
            TvStyle.cardFocus(card,null);card.setBackground(focusRing(MultiviewActivity.this));TvStyle.scaleOnFocus(card,null,focused->TvStyle.glow(frame,focused));
            return new RecyclerView.ViewHolder(card){};
        }
        @Override public void onBindViewHolder(RecyclerView.ViewHolder holder,int index){
            Entry e=list.get(index);LinearLayout card=(LinearLayout)holder.itemView;FrameLayout frame=(FrameLayout)card.getChildAt(0);
            boolean running=false;for(Slot s:slots)if(s.entry.id.equals(e.id))running=true;
            ImageView logo=(ImageView)frame.getChildAt(0);artwork.load(logo,e.image,true);
            ((TextView)card.getChildAt(1)).setText((running?"✓ ":"")+lists.name(e));card.setAlpha(running?.5f:1f);
            card.setContentDescription(lists.name(e)+(running?", läuft schon":""));card.setOnClickListener(v->choose(e,replace));
        }
    }
    static StateListDrawable focusRing(android.content.Context c){StateListDrawable bg=new StateListDrawable();bg.addState(new int[]{android.R.attr.state_focused},TvStyle.focusRing(c,TvStyle.R_CARD));bg.addState(new int[]{},new ColorDrawable(0));return bg;}

    /** Die Leiste blendet sich nach 3 s aus (ausser ohne Bilder oder während der Senderwahl); der Fokus geht dann aufs Bild mit Ton. */
    private void setControls(boolean visible){
        if(bar==null||(!visible&&(slots.isEmpty()||picker!=null)))return;
        if(!visible&&bar.hasFocus())slots.get(Math.max(0,slots.indexOf(audio))).tile.requestFocus();
        bar.setVisibility(visible?View.VISIBLE:View.INVISIBLE);
    }
    private void reveal(){setControls(true);main.removeCallbacks(hide);main.postDelayed(hide,HIDE_MS);}
    /** Leiste nach 3 s ausblenden; nach geschlossener Senderwahl startet der Zeitgeber neu (`closePicker`). */
    private static final long HIDE_MS=3000;
    @Override public boolean dispatchKeyEvent(KeyEvent event){
        if(event.getAction()==KeyEvent.ACTION_DOWN&&picker==null&&event.getKeyCode()!=KeyEvent.KEYCODE_BACK){boolean hidden=bar.getVisibility()!=View.VISIBLE;reveal();
            if(hidden&&(event.getKeyCode()==KeyEvent.KEYCODE_DPAD_UP))return true;}
        if(event.getAction()==KeyEvent.ACTION_DOWN&&event.getKeyCode()==KeyEvent.KEYCODE_MENU&&picker==null){View f=getCurrentFocus();for(Slot s:slots)if(s.tile==f){menu(s);return true;}}
        return super.dispatchKeyEvent(event);
    }
    @Override protected void onStart(){super.onStart();started=true;for(Slot s:slots)if(s.player==null)start(s);refresh();}
    @Override protected void onStop(){started=false;for(Slot s:slots)stop(s);main.removeCallbacks(hide);super.onStop();}
    @Override public void onBackPressed(){if(picker!=null){closePicker();if(!slots.isEmpty())slots.get(0).tile.requestFocus();return;}finish();}
    @Override protected void onDestroy(){main.removeCallbacksAndMessages(null);if(artwork!=null)artwork.close();super.onDestroy();}
}
