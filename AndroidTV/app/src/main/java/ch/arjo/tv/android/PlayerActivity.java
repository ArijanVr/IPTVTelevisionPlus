package ch.arjo.tv.android;

import android.app.*;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.os.SystemClock;
import android.widget.FrameLayout;
import android.widget.GridLayout;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Button;
import android.graphics.Color;
import android.content.*;
import android.view.*;
import android.widget.Toast;
import androidx.media3.common.*;
import androidx.media3.datasource.DefaultHttpDataSource;
import androidx.media3.exoplayer.*;
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory;
import androidx.media3.session.MediaSession;
import androidx.media3.ui.PlayerView;
import java.util.List;
import java.util.concurrent.*;

@androidx.media3.common.util.UnstableApi
public final class PlayerActivity extends Activity {
    private Player player;
    private PlayerView video;
    private MediaSession session;
    private boolean live,playWhenReady=true,menuMode,restoringQueue;
    private String url,key,name,entryId,group,scope,queueToken;
    private long position;
    private SharedPreferences progress;
    private AlertDialog error;
    private PlaybackQueue queue;
    private RemoteInput remote;
    private Toast feedback;
    private final Handler ui=new Handler(Looper.getMainLooper());
    private final ChannelNavigator digitsNav=new ChannelNavigator(java.util.Collections.<String>emptyList());
    private TextView groupBanner,channelNumber,channelName,entryView,padDisplay;
    private LinearLayout channelBanner;
    private Runnable hideGroup,hideBanner,commitTask,groupStart,hideEntry;
    private String pendingGroupName;
    private int currentNumber;
    private AlertDialog pad;
    private final ExecutorService worker=Executors.newSingleThreadExecutor();
    /** Regeln für Wiederholung, Formatwechsel, Stillstand und Zappen (wie Samsung TV). */
    private final PlaybackGuard guard=new PlaybackGuard();
    private Runnable openTask,watchTask;
    /** Nur der erste Start nach onStart übernimmt den gesicherten Pausenzustand; Wiederholungen und Senderwechsel spielen ab. */
    private boolean openPlaying=true;
    private boolean stallReported;
    @Override public void onCreate(Bundle state){
        super.onCreate(state);androidx.media3.common.util.Log.setLogLevel(androidx.media3.common.util.Log.LOG_LEVEL_OFF);TvStyle.fullscreen(this);
        getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        url=value(state,"url");key=value(state,"key");name=value(state,"name");entryId=value(state,"entryId");group=value(state,"group");scope=value(state,"scope");queueToken=value(state,"queueToken");
        live=getIntent().getBooleanExtra("live",true);
        if(url==null||key==null||!Source.isWeb(url)){finish();return;}
        queue=PlaybackQueue.get(queueToken);if(queue!=null&&entryId!=null)queue.select(entryId);
        progress=getSharedPreferences("progress",0);position=state==null?(live?0:progress.getLong(key,0)):state.getLong("position",0);playWhenReady=state==null||state.getBoolean("playing",true);
        video=new PlayerView(this);video.setBackgroundColor(TvStyle.BLACK);video.setShowBuffering(PlayerView.SHOW_BUFFERING_WHEN_PLAYING);
        video.setShowNextButton(false);video.setShowPreviousButton(false);video.setShowSubtitleButton(true);
        video.setControllerAutoShow(false);video.setControllerShowTimeoutMs(5000);
        video.setControllerVisibilityListener((PlayerView.ControllerVisibilityListener)visibility->{if(visibility!=View.VISIBLE)menuMode=false;});
        video.hideController();buildOverlays();video.requestFocus();
        if(queue!=null)currentNumber=queue.current().number;
        remote=new RemoteInput(new RemoteInput.Host(){
            public boolean live(){return live;}
            public boolean menuOpen(){return menuMode&&video.isControllerFullyVisible();}
            public void channel(int direction){changeChannel(direction);}
            public void seek(long deltaMs){seekBy(deltaMs);}
            public void openMenu(){menuMode=true;video.showController();}
            public void group(int direction){switchGroup(direction);}
            public void digit(int digit){enterDigit(digit);}
            public void commit(){commitDigits();}
            public boolean pendingDigits(){return digitsNav.hasPendingDigits();}
            public void info(){showBanner();}
            public void numberPad(){showNumberPad();}
            public void recall(){recallPrevious();}
        });
    }
    private String value(Bundle state,String key){return state!=null&&state.containsKey(key)?state.getString(key):getIntent().getStringExtra(key);}
    @Override protected void onStart(){
        super.onStart();if(video==null)return;
        DefaultHttpDataSource.Factory http=new DefaultHttpDataSource.Factory().setUserAgent("ARJOTV-Android/0.2")
            .setConnectTimeoutMs(15000).setReadTimeoutMs(20000);
        // Live: Bild nach 1 s Puffer statt 2.5 s (schnelleres Umschalten), nach Aussetzern 3 s, damit es nicht ruckelt.
        DefaultLoadControl load=new DefaultLoadControl.Builder().setBufferDurationsMs(15000,50000,live?1000:2500,live?3000:5000).build();
        player=new ExoPlayer.Builder(this).setLoadControl(load).setRenderersFactory(new DefaultRenderersFactory(this).setEnableDecoderFallback(true))
            .setMediaSourceFactory(new DefaultMediaSourceFactory(this).setDataSourceFactory(http)).setSeekBackIncrementMs(10000).setSeekForwardIncrementMs(10000).build();
        video.setPlayer(player);
        player.addListener(new Player.Listener(){
            @Override public void onPlayerError(PlaybackException exception){
                if(isFinishing()||isDestroyed()||player==null)return;
                handleError(exception.errorCode);
            }
            @Override public void onPlaybackStateChanged(int state){
                if(state==Player.STATE_ENDED&&!live){position=0;progress.edit().remove(key).apply();}
                if(state==Player.STATE_BUFFERING&&guard.hasStarted()){guard.buffering(SystemClock.uptimeMillis());PlaybackDiag.log(PlayerActivity.this,"buffering","");}
            }
            @Override public void onIsPlayingChanged(boolean isPlaying){
                if(!isPlaying||player==null)return;
                boolean first=!guard.hasStarted();guard.playing(SystemClock.uptimeMillis());stallReported=false;
                if(first){
                    String format=PlaybackGuard.format(guard.url());
                    if(live&&!format.isEmpty()&&!format.equals(preferredFormat())){getSharedPreferences("library",0).edit().putString("liveFormat",format).apply();PlaybackDiag.log(PlayerActivity.this,"format-preferred",format);}
                    PlaybackDiag.log(PlayerActivity.this,"playing","format="+format+" retry="+guard.retries());
                }
            }
        });
        session=new MediaSession.Builder(this,player).build();openPlaying=playWhenReady;select(live?0:position);video.hideController();
        if(live&&queue==null)restoreQueue();
        startWatch();
    }
    private String preferredFormat(){return getSharedPreferences("library",0).getString("liveFormat","");}
    /** Neuer Sender/Film: alten Stream schliessen, nach Zapp-Ruhe bzw. Mindestabstand öffnen (nie zwei Verbindungen). */
    private void select(long startMs){
        if(player==null)return;
        long now=SystemClock.uptimeMillis();
        if(player.getPlaybackState()!=Player.STATE_IDLE){player.stop();guard.closed(now);}
        long wait=guard.select(url,live,preferredFormat(),now);
        PlaybackDiag.log(this,"select","live="+live+" wait="+wait);
        scheduleOpen(wait,startMs);
    }
    private void scheduleOpen(long waitMs,long startMs){
        if(openTask!=null)ui.removeCallbacks(openTask);
        openTask=()->{openTask=null;if(player==null||isFinishing())return;PlaybackDiag.log(this,"attempt","format="+PlaybackGuard.format(guard.url())+" retry="+guard.retries());
            setCurrentMedia();if(startMs>0)player.seekTo(startMs);player.prepare();player.setPlayWhenReady(openPlaying);openPlaying=true;};
        ui.postDelayed(openTask,Math.max(0,waitMs));
    }
    private void handleError(int code){
        long now=SystemClock.uptimeMillis();
        long resumeAt=live?0:Math.max(0,player.getCurrentPosition());
        PlaybackGuard.Decision d=guard.error(code,now);
        PlaybackDiag.log(this,"error","code="+code+" kind="+d.kind+" action="+d.action+" started="+guard.hasStarted());
        if(d.action==PlaybackGuard.Action.REPREPARE){player.seekToDefaultPosition();player.prepare();player.play();return;}
        player.stop();guard.closed(now);
        if(d.action==PlaybackGuard.Action.VARIANT){scheduleOpen(guard.openDelay(now),resumeAt);return;}
        if(d.action==PlaybackGuard.Action.RETRY){
            message("Keine Verbindung, neuer Versuch in "+(d.delayMs/1000)+" s …");
            scheduleOpen(Math.max(d.delayMs,guard.openDelay(now)),resumeAt);return;
        }
        if(live&&(d.kind==PlaybackGuard.Kind.FORMAT||d.kind==PlaybackGuard.Kind.UNAVAILABLE)){message("Sender momentan nicht verfügbar. Mit Hoch/Runter einen anderen Sender wählen.");return;}
        showFailure(d.kind==PlaybackGuard.Kind.CONNECTION
            ?"Keine Verbindung zum Stream nach mehreren Versuchen. Dein Zugang erlaubt eventuell nur eine Verbindung gleichzeitig: andere Geräte und Apps schliessen und erneut versuchen."
            :"Stream oder Format ist momentan nicht verfügbar. Prüfe die Verbindung. Einige Ton-/Bildformate werden vom Fernseher möglicherweise nicht unterstützt.",resumeAt);
    }
    /** Meldung nach ausgeschöpften Versuchen mit gezieltem neuem Versuch (setzt alle Grenzen zurück). */
    private void showFailure(String text,long resumeAt){
        if(isFinishing()||isDestroyed()||(error!=null&&error.isShowing()))return;
        error=new AlertDialog.Builder(this).setTitle(live?"Sender nicht verfügbar":"Wiedergabe unterbrochen").setMessage(text)
            .setPositiveButton("Erneut versuchen",(d,n)->{PlaybackDiag.log(this,"user-retry","");select(resumeAt);})
            .setNegativeButton(live?"Schliessen":"Zurück",(d,n)->{if(!live)finish();}).create();error.show();
    }
    /** Alle 2 s: Zähler nach stabiler Wiedergabe zurücksetzen, hängendes Live-Bild neu laden (begrenzt). */
    private void startWatch(){
        if(watchTask!=null)ui.removeCallbacks(watchTask);
        watchTask=new Runnable(){public void run(){
            if(player==null)return;long now=SystemClock.uptimeMillis();
            if(guard.stable(now))PlaybackDiag.log(PlayerActivity.this,"stable","");
            boolean waiting=player.getPlayWhenReady()&&openTask==null;
            if(guard.stalled(now,waiting)){
                PlaybackDiag.log(PlayerActivity.this,"stall","recoveries="+guard.recoveryCount());message("Bild hängt, Sender wird neu geladen …");
                player.stop();guard.closed(now);scheduleOpen(guard.openDelay(now),0);
            }else if(!stallReported&&guard.stallGiveUp(now,waiting)){
                stallReported=true;PlaybackDiag.log(PlayerActivity.this,"stall-giveup","");player.stop();guard.closed(now);
                showFailure("Das Bild ist mehrmals stehen geblieben. Prüfe die Verbindung des Fernsehers oder versuche es erneut.",0);
            }
            ui.postDelayed(this,2000);
        }};
        ui.postDelayed(watchTask,2000);
    }
    private void setCurrentMedia(){player.setMediaItem(new MediaItem.Builder().setUri(guard.url()).setMediaMetadata(new MediaMetadata.Builder().setTitle(name).build()).build());}
    private void changeChannel(int direction){
        if(player==null)return;
        if(queue==null){restoreQueue();message("Senderliste wird geladen …");return;}
        if(queue.size()<2){message("In dieser Gruppe ist nur ein Sender vorhanden.");return;}
        playEntry(queue.move(direction));
    }
    private void playEntry(Entry next){
        url=next.url;name=next.name;entryId=next.id;group=next.group;currentNumber=next.number;key=Source.hash(scope+"|"+next.id);position=0;
        if(error!=null)error.dismiss();menuMode=false;video.hideController();select(0);
        setResult(RESULT_OK,new Intent().putExtra("entryId",entryId));showBanner();
    }
    /** Links/rechts: Gruppe wechseln. Schnelles Mehrfachdrücken aktualisiert nur das Banner, gestartet wird die letzte Gruppe. */
    private void switchGroup(int direction){
        if(queue==null||!live)return;
        ChannelNavigator.GroupPosition target=queue.neighbourGroup(pendingGroupName!=null?pendingGroupName:group,direction);
        if(target==null)return;
        pendingGroupName=target.name;groupBanner.setText(target.name+" · "+target.position+" von "+target.count);groupBanner.setVisibility(View.VISIBLE);
        if(hideGroup!=null)ui.removeCallbacks(hideGroup);hideGroup=()->groupBanner.setVisibility(View.GONE);ui.postDelayed(hideGroup,2000);
        if(groupStart!=null)ui.removeCallbacks(groupStart);
        groupStart=()->{String wanted=pendingGroupName;pendingGroupName=null;Entry first=wanted==null||queue==null?null:queue.startGroup(wanted);if(first!=null&&player!=null)playEntry(first);};
        ui.postDelayed(groupStart,250);
    }
    private void enterDigit(int digit){
        if(!live)return;
        digitsNav.enter(digit,SystemClock.uptimeMillis());showEntry(digitsNav.digits());if(padDisplay!=null)padDisplay.setText(digitsNav.digits());
        if(commitTask!=null)ui.removeCallbacks(commitTask);commitTask=this::commitDigits;ui.postDelayed(commitTask,ChannelNavigator.DIGIT_WINDOW_MS);
    }
    private void commitDigits(){
        if(commitTask!=null)ui.removeCallbacks(commitTask);
        int number=digitsNav.commitDigits();entryView.setVisibility(View.GONE);if(padDisplay!=null)padDisplay.setText("–");
        if(number<=0||queue==null||player==null)return;
        Entry target=queue.byNumber(number);
        if(target==null){showEntry("Kanal "+number+" nicht vorhanden",2000);return;}
        if(target.id.equals(entryId)){showBanner();return;}
        playEntry(queue.jump(target));
    }
    private void cancelDigits(){
        if(commitTask!=null)ui.removeCallbacks(commitTask);digitsNav.cancelDigits();entryView.setVisibility(View.GONE);if(padDisplay!=null)padDisplay.setText("–");
    }
    private void recallPrevious(){
        if(queue==null||player==null)return;Entry previous=queue.previous();if(previous!=null)playEntry(previous);
    }
    private void showEntry(String text){
        entryView.setText(text);entryView.setVisibility(View.VISIBLE);if(hideEntry!=null)ui.removeCallbacks(hideEntry);
    }
    private void showEntry(String text,long forMs){
        showEntry(text);hideEntry=()->entryView.setVisibility(View.GONE);ui.postDelayed(hideEntry,forMs);
    }
    /** Kanal-Banner unten: Nummer und Name (Android hat kein EPG), nach 4 Sekunden weg. */
    private void showBanner(){
        if(!live||channelBanner==null)return;
        channelNumber.setText(currentNumber>0?String.valueOf(currentNumber):"");channelNumber.setVisibility(currentNumber>0?View.VISIBLE:View.GONE);channelName.setText(name==null?"":name);
        channelBanner.setVisibility(View.VISIBLE);if(hideBanner!=null)ui.removeCallbacks(hideBanner);
        hideBanner=()->channelBanner.setVisibility(View.GONE);ui.postDelayed(hideBanner,4000);
    }
    /** Zahlenfeld 3 × 4 für Fernbedienungen ohne Zifferntasten. */
    private void showNumberPad(){
        if(!live||isFinishing()||(pad!=null&&pad.isShowing()))return;
        LinearLayout box=TvStyle.column(this);TvStyle.pad(this,box,24,16);
        padDisplay=TvStyle.title(this,digitsNav.hasPendingDigits()?digitsNav.digits():"–",40);padDisplay.setGravity(Gravity.CENTER);padDisplay.setContentDescription("Kanalnummer");box.addView(padDisplay);
        GridLayout grid=new GridLayout(this);grid.setColumnCount(3);
        String[] labels={"1","2","3","4","5","6","7","8","9","✕","0","OK"};
        for(int i=0;i<labels.length;i++){
            String label=labels[i];
            Runnable action=label.equals("✕")?()->{cancelDigits();if(pad!=null)pad.dismiss();}:label.equals("OK")?()->{commitDigits();if(pad!=null)pad.dismiss();}:()->enterDigit(Integer.parseInt(label));
            Button b=TvStyle.button(this,label,label.equals("OK"),action);
            b.setContentDescription(label.equals("✕")?"Abbrechen":label.equals("OK")?"Bestätigen":"Ziffer "+label);
            GridLayout.LayoutParams p=new GridLayout.LayoutParams();p.width=TvStyle.dp(this,84);p.height=TvStyle.dp(this,52);p.setMargins(6,6,6,6);grid.addView(b,p);
        }
        box.addView(grid);
        pad=new AlertDialog.Builder(this).setView(box).create();pad.setOnDismissListener(d->{padDisplay=null;pad=null;});pad.show();
    }
    private void buildOverlays(){
        FrameLayout root=new FrameLayout(this);root.setBackgroundColor(TvStyle.BLACK);root.addView(video,new FrameLayout.LayoutParams(-1,-1));
        int panel=0xCC090A0A;
        groupBanner=TvStyle.title(this,"",22);groupBanner.setVisibility(View.GONE);groupBanner.setBackground(TvStyle.shape(panel,Color.TRANSPARENT,14));TvStyle.pad(this,groupBanner,24,10);
        FrameLayout.LayoutParams gp=new FrameLayout.LayoutParams(-2,-2,Gravity.TOP|Gravity.CENTER_HORIZONTAL);gp.topMargin=TvStyle.dp(this,28);root.addView(groupBanner,gp);
        channelBanner=TvStyle.row(this);channelBanner.setGravity(Gravity.CENTER_VERTICAL);channelBanner.setVisibility(View.GONE);channelBanner.setBackground(TvStyle.shape(panel,Color.TRANSPARENT,14));TvStyle.pad(this,channelBanner,24,14);
        channelNumber=TvStyle.title(this,"",40);channelName=TvStyle.title(this,"",24);
        LinearLayout.LayoutParams np=new LinearLayout.LayoutParams(-2,-2);np.rightMargin=TvStyle.dp(this,20);channelBanner.addView(channelNumber,np);channelBanner.addView(channelName);
        FrameLayout.LayoutParams cp=new FrameLayout.LayoutParams(-2,-2,Gravity.BOTTOM|Gravity.START);cp.leftMargin=TvStyle.dp(this,48);cp.bottomMargin=TvStyle.dp(this,40);root.addView(channelBanner,cp);
        entryView=TvStyle.title(this,"",44);entryView.setVisibility(View.GONE);entryView.setBackground(TvStyle.shape(panel,Color.TRANSPARENT,18));TvStyle.pad(this,entryView,32,14);
        root.addView(entryView,new FrameLayout.LayoutParams(-2,-2,Gravity.CENTER));
        for(View v:new View[]{groupBanner,channelBanner,entryView}){v.setFocusable(false);v.setClickable(false);}
        setContentView(root);
    }
    private void seekBy(long delta){
        if(player==null||live)return;
        if(!player.isCurrentMediaItemSeekable()||!player.isCommandAvailable(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)){message("Dieser Stream lässt sich momentan nicht spulen.");return;}
        long target=RemoteInput.target(player.getCurrentPosition(),player.getDuration(),delta);player.seekTo(target);
        // Do not reveal the focusable controller while using direct seek shortcuts.
        message((delta>0?"+":"−")+(Math.abs(delta)/1000)+" s · "+clock(target));
    }
    private static String clock(long millis){long seconds=Math.max(0,millis/1000);return String.format(java.util.Locale.ROOT,"%d:%02d",seconds/60,seconds%60);}
    private void message(String text){if(feedback!=null)feedback.cancel();feedback=Toast.makeText(this,text,Toast.LENGTH_SHORT);feedback.show();}
    private void restoreQueue(){
        if(restoringQueue||scope==null||entryId==null)return;restoringQueue=true;
        String expectedId=entryId,expectedUrl=url,expectedName=name,expectedGroup=group,expectedScope=scope;
        worker.execute(()->{
            PlaybackQueue restored=null;
            try{Vault vault=new Vault(this);Source source=vault.load();if(source!=null&&source.scope().equals(expectedScope)){
                // Zuerst der lokale Zwischenspeicher (sofort da), nur ohne ihn aus dem Netz.
                CatalogCache.Hit hit=new CatalogCache(this,vault::cacheKey).load(expectedScope,source.mode.equals("m3u")?"playlist":"live");
                List<Entry> loaded=hit!=null&&!hit.entries.isEmpty()?hit.entries:new Catalog(source).load("live");NumberStore.apply(getSharedPreferences("library",0),expectedScope,loaded,false);restored=new PlaybackQueue(loaded,new Entry(expectedId,expectedName,expectedGroup,expectedUrl,"live"),expectedScope);}}catch(Exception ignored){}
            PlaybackQueue result=restored;
            runOnUiThread(()->{restoringQueue=false;if(isDestroyed()||isFinishing()||result==null)return;queue=result;queueToken=PlaybackQueue.register(result);});
        });
    }
    private void save(){
        if(player==null)return;playWhenReady=player.getPlayWhenReady();
        if(!live){long duration=player.getDuration();position=player.getCurrentPosition();if(player.getPlaybackState()==Player.STATE_ENDED||(duration>0&&duration-position<10000))position=0;
            SharedPreferences.Editor edit=progress.edit().putLong(key,position);if(duration>0)edit.putLong(key+":duration",duration);edit.apply();}
    }
    @Override protected void onSaveInstanceState(Bundle state){
        save();state.putLong("position",position);state.putBoolean("playing",playWhenReady);
        state.putString("url",url);state.putString("key",key);state.putString("name",name);state.putString("entryId",entryId);state.putString("group",group);state.putString("scope",scope);state.putString("queueToken",queueToken);super.onSaveInstanceState(state);
    }
    @Override protected void onStop(){if(openTask!=null){ui.removeCallbacks(openTask);openTask=null;}if(watchTask!=null){ui.removeCallbacks(watchTask);watchTask=null;}save();if(error!=null)error.dismiss();if(session!=null){session.release();session=null;}if(player!=null){video.setPlayer(null);player.release();player=null;}menuMode=false;super.onStop();}
    @Override public boolean dispatchKeyEvent(KeyEvent event){return (remote!=null&&remote.key(event))||super.dispatchKeyEvent(event);}
    @Override public boolean onGenericMotionEvent(MotionEvent event){return (remote!=null&&remote.motion(event))||super.onGenericMotionEvent(event);}
    @Override public void onBackPressed(){
        if(digitsNav.hasPendingDigits()){cancelDigits();return;}
        if(video!=null&&video.isControllerFullyVisible()){menuMode=false;video.hideController();return;}
        finish();
    }
    @Override protected void onDestroy(){ui.removeCallbacksAndMessages(null);worker.shutdownNow();if(feedback!=null)feedback.cancel();if(isFinishing())PlaybackQueue.clear(queueToken);super.onDestroy();}
}
