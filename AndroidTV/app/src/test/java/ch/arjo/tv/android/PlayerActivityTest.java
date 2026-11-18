package ch.arjo.tv.android;

import android.content.Intent;
import android.os.Bundle;
import android.view.KeyEvent;
import androidx.media3.common.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import org.robolectric.android.controller.ActivityController;
import java.lang.reflect.*;
import java.util.*;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=28)
public class PlayerActivityTest {
    private ActivityController<PlayerActivity> controller;
    private PlayerActivity activity;
    private Recording backend;
    private String token;
    private final Entry first=new Entry("live:1","First","CH","https://example.test/1.ts","live"),second=new Entry("live:2","Second","CH","https://example.test/2.ts","live");
    private static final class Recording implements InvocationHandler {
        long position=50000,duration=120000;boolean seekable=true;int prepares,plays;MediaItem item;
        public Object invoke(Object proxy,Method method,Object[] args){switch(method.getName()){
            case "getCurrentPosition":return position;case "getDuration":return duration;case "getPlayWhenReady":return true;case "getPlaybackState":return Player.STATE_READY;
            case "isCurrentMediaItemSeekable":case "isCommandAvailable":return seekable;
            case "seekTo":position=(Long)args[args.length-1];return null;case "setMediaItem":item=(MediaItem)args[0];return null;
            case "prepare":prepares++;return null;case "play":plays++;return null;case "setPlayWhenReady":if((Boolean)args[0])plays++;return null;
            case "toString":return "RecordingPlayer";case "hashCode":return System.identityHashCode(proxy);case "equals":return proxy==args[0];
            default:if(method.getReturnType()==boolean.class)return false;if(method.getReturnType()==int.class)return 0;if(method.getReturnType()==long.class)return 0L;return null;
        }}
    }
    private void create(boolean live)throws Exception{
        String scope="fixture-scope";PlaybackQueue queue=new PlaybackQueue(Arrays.asList(first,second),first,scope);token=PlaybackQueue.register(queue);
        Intent intent=new Intent(RuntimeEnvironment.getApplication(),PlayerActivity.class).putExtra("url",first.url).putExtra("key",Source.hash(scope+"|"+first.id)).putExtra("name",first.name).putExtra("entryId",first.id).putExtra("group","CH").putExtra("scope",scope).putExtra("queueToken",token).putExtra("live",live);
        // Only create the view. Inject a recording Player before onStart to avoid any network/decoder activity.
        controller=Robolectric.buildActivity(PlayerActivity.class,intent).create();activity=controller.get();backend=new Recording();
        Player fake=(Player)Proxy.newProxyInstance(Player.class.getClassLoader(),new Class[]{Player.class},backend);Field field=PlayerActivity.class.getDeclaredField("player");field.setAccessible(true);field.set(activity,fake);
    }
    private void tap(int code){assertTrue(activity.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN,code)));assertTrue(activity.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_UP,code)));}
    @After public void close(){if(controller!=null)controller.destroy();PlaybackQueue.clear(token);}
    /** Senderwechsel: alter Stream wird geschlossen, der neue erst nach kurzer Ruhe geöffnet (PlaybackGuard). */
    private void settle(){org.robolectric.shadows.ShadowLooper.idleMainLooper(PlaybackGuard.ZAP_GAP_MS+100,java.util.concurrent.TimeUnit.MILLISECONDS);}
    @Test public void liveArrowChangesStreamAndDoesNotSeekOrOpenASecondActivity()throws Exception{create(true);tap(KeyEvent.KEYCODE_DPAD_UP);assertNull("noch nicht geöffnet",backend.item);settle();assertNotNull(backend.item);assertEquals(second.url,backend.item.localConfiguration.uri.toString());assertEquals(1,backend.prepares);assertEquals(1,backend.plays);assertEquals(50000,backend.position);tap(KeyEvent.KEYCODE_DPAD_DOWN);settle();assertEquals(first.url,backend.item.localConfiguration.uri.toString());}
    @Test public void filmLeftRightChangesPositionWithoutChangingStream()throws Exception{create(false);tap(KeyEvent.KEYCODE_DPAD_RIGHT);assertEquals(60000,backend.position);tap(KeyEvent.KEYCODE_DPAD_LEFT);assertEquals(50000,backend.position);assertNull(backend.item);assertEquals(0,backend.prepares);}
    @Test public void seekClampsAtStartAndEndAndHonorsUnseekableStreams()throws Exception{create(false);backend.position=115000;tap(KeyEvent.KEYCODE_DPAD_RIGHT);assertEquals(120000,backend.position);backend.position=5000;tap(KeyEvent.KEYCODE_DPAD_LEFT);assertEquals(0,backend.position);backend.seekable=false;tap(KeyEvent.KEYCODE_DPAD_RIGHT);assertEquals(0,backend.position);}
    @Test public void savingAfterChannelChangeStoresTheCurrentChannelIdentity()throws Exception{create(true);tap(KeyEvent.KEYCODE_DPAD_UP);Bundle saved=new Bundle();controller.saveInstanceState(saved);assertEquals(second.id,saved.getString("entryId"));assertEquals(second.url,saved.getString("url"));assertEquals(Source.hash("fixture-scope|"+second.id),saved.getString("key"));}
}
