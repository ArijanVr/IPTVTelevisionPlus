package ch.arjo.tv.android;

import android.view.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=28,manifest=Config.NONE)
public class RemoteInputTest {
    private final Host host=new Host();
    private final RemoteInput input=new RemoteInput(host);
    private static class Host implements RemoteInput.Host {
        boolean live,menu;int channels,opens;long seek;
        public boolean live(){return live;}public boolean menuOpen(){return menu;}
        public void channel(int direction){channels+=direction;}public void seek(long delta){seek+=delta;}public void openMenu(){menu=true;opens++;}
    }
    private KeyEvent key(int action,int code,long time,int repeat){return new KeyEvent(0,time,action,code,repeat);}
    private void tap(int code){assertTrue(input.key(key(KeyEvent.ACTION_DOWN,code,10,0)));assertTrue(input.key(key(KeyEvent.ACTION_UP,code,20,0)));}
    private MotionEvent wheel(int source,int axis,float delta,long time){
        MotionEvent.PointerProperties prop=new MotionEvent.PointerProperties();prop.id=0;
        MotionEvent.PointerCoords coords=new MotionEvent.PointerCoords();coords.setAxisValue(axis,delta);
        return MotionEvent.obtain(0,time,MotionEvent.ACTION_SCROLL,1,new MotionEvent.PointerProperties[]{prop},new MotionEvent.PointerCoords[]{coords},0,0,1,1,0,0,source,0);
    }
    @Test public void liveUpDownAndChannelKeysSwitchExactlyOncePerTap(){host.live=true;tap(KeyEvent.KEYCODE_DPAD_UP);assertEquals(1,host.channels);tap(KeyEvent.KEYCODE_DPAD_DOWN);assertEquals(0,host.channels);tap(KeyEvent.KEYCODE_CHANNEL_UP);tap(KeyEvent.KEYCODE_CHANNEL_DOWN);assertEquals(0,host.channels);assertEquals(0,host.seek);}
    @Test public void filmAndEpisodeLeftRightSeekTenSeconds(){tap(KeyEvent.KEYCODE_DPAD_RIGHT);assertEquals(10000,host.seek);tap(KeyEvent.KEYCODE_DPAD_LEFT);assertEquals(0,host.seek);assertEquals(0,host.channels);}
    @Test public void heldKeysAreThrottledAndFilmSeekAccelerates(){
        input.key(key(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_RIGHT,10,0));input.key(key(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_RIGHT,30,1));assertEquals(10000,host.seek);
        input.key(key(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_RIGHT,200,5));assertEquals(40000,host.seek);
    }
    @Test public void heldChannelKeyDoesNotRapidlyOpenManyStreams(){host.live=true;input.key(key(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_UP,10,0));input.key(key(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_UP,100,1));assertEquals(1,host.channels);input.key(key(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_UP,320,2));assertEquals(2,host.channels);}
    @Test public void okOpensMenuAndDoesNotTriggerTwiceOnRelease(){tap(KeyEvent.KEYCODE_DPAD_CENTER);assertEquals(1,host.opens);assertTrue(host.menu);assertFalse(input.key(key(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_RIGHT,30,0)));assertEquals(0,host.seek);}
    @Test public void visibleMenusKeepArrowNavigationWhileChannelButtonsStillWork(){host.live=true;host.menu=true;assertFalse(input.key(key(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_UP,10,0)));assertEquals(0,host.channels);tap(KeyEvent.KEYCODE_CHANNEL_UP);assertEquals(1,host.channels);}
    @Test public void backHomeAndVolumeRemainSystemKeys(){for(int code:new int[]{KeyEvent.KEYCODE_BACK,KeyEvent.KEYCODE_HOME,KeyEvent.KEYCODE_VOLUME_UP})assertFalse(input.key(key(KeyEvent.ACTION_DOWN,code,10,0)));}
    @Test public void rotaryInputAccumulatesSmallStepsAndSupportsBothDirections(){
        MotionEvent a=wheel(InputDevice.SOURCE_ROTARY_ENCODER,MotionEvent.AXIS_SCROLL,.6f,10),b=wheel(InputDevice.SOURCE_ROTARY_ENCODER,MotionEvent.AXIS_SCROLL,.6f,20),c=wheel(InputDevice.SOURCE_ROTARY_ENCODER,MotionEvent.AXIS_SCROLL,-1,30);
        try{assertTrue(input.motion(a));assertEquals(0,host.seek);assertTrue(input.motion(b));assertEquals(10000,host.seek);assertTrue(input.motion(c));assertEquals(0,host.seek);}finally{a.recycle();b.recycle();c.recycle();}
    }
    @Test public void largeWheelDeltaIsCappedWithoutLeavingQueuedJumps(){MotionEvent a=wheel(InputDevice.SOURCE_ROTARY_ENCODER,MotionEvent.AXIS_SCROLL,20,10),b=wheel(InputDevice.SOURCE_ROTARY_ENCODER,MotionEvent.AXIS_SCROLL,.2f,20);try{input.motion(a);assertEquals(30000,host.seek);input.motion(b);assertEquals(30000,host.seek);}finally{a.recycle();b.recycle();}}
    @Test public void verticalScrollWheelChangesLiveChannels(){host.live=true;MotionEvent event=wheel(InputDevice.SOURCE_MOUSE,MotionEvent.AXIS_VSCROLL,1,10);try{assertTrue(input.motion(event));assertEquals(1,host.channels);}finally{event.recycle();}}
    @Test public void wheelInsideMenuDoesNotSeek(){host.menu=true;MotionEvent event=wheel(InputDevice.SOURCE_ROTARY_ENCODER,MotionEvent.AXIS_SCROLL,1,10);try{assertFalse(input.motion(event));assertEquals(0,host.seek);}finally{event.recycle();}}
    @Test public void seekBoundsHandleStartEndAndUnknownDuration(){assertEquals(0,RemoteInput.target(5000,120000,-10000));assertEquals(120000,RemoteInput.target(115000,120000,10000));assertEquals(60000,RemoteInput.target(50000,-1,10000));assertEquals(Long.MAX_VALUE,RemoteInput.target(Long.MAX_VALUE-1,-1,10000));}
}
