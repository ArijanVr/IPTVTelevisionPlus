package ch.arjo.tv.android;

import android.view.*;
import java.util.HashSet;
import java.util.Set;

/** Direct playback shortcuts, leaving directional focus inside the opened controller intact. */
final class RemoteInput {
    interface Host {
        boolean live(); boolean menuOpen();
        void channel(int direction); void seek(long deltaMs); void openMenu();
        /** Live: Gruppe wechseln (links/rechts). */
        default void group(int direction){}
        default void digit(int digit){}
        /** OK bei laufender Zifferneingabe: Nummer sofort wählen. */
        default void commit(){}
        default boolean pendingDigits(){return false;}
        /** OK kurz im Live-Bild: Kanal-Banner zeigen. */
        default void info(){}
        /** OK lang im Live-Bild: Zahlenfeld. */
        default void numberPad(){}
        default void recall(){}
    }
    private final Host host;
    private final Set<Integer> captured=new HashSet<>();
    private long lastAction=Long.MIN_VALUE,lastGroup=Long.MIN_VALUE;
    private boolean longDone;
    private float scroll;
    RemoteInput(Host host){this.host=host;}
    boolean key(KeyEvent event){
        int code=event.getKeyCode();
        boolean center=code==KeyEvent.KEYCODE_DPAD_CENTER||code==KeyEvent.KEYCODE_ENTER||code==KeyEvent.KEYCODE_NUMPAD_ENTER;
        if(event.getAction()==KeyEvent.ACTION_UP){
            boolean was=captured.remove(code);
            if(was&&center&&host.live()&&!host.menuOpen()&&!longDone){if(host.pendingDigits())host.commit();else host.info();}
            return was;
        }
        if(event.getAction()!=KeyEvent.ACTION_DOWN)return false;
        if(host.live()&&!host.menuOpen()){
            int digit=code>=KeyEvent.KEYCODE_0&&code<=KeyEvent.KEYCODE_9?code-KeyEvent.KEYCODE_0:code>=KeyEvent.KEYCODE_NUMPAD_0&&code<=KeyEvent.KEYCODE_NUMPAD_9?code-KeyEvent.KEYCODE_NUMPAD_0:-1;
            if(digit>=0){captured.add(code);if(event.getRepeatCount()==0)host.digit(digit);return true;}
            if(code==KeyEvent.KEYCODE_LAST_CHANNEL){captured.add(code);if(event.getRepeatCount()==0)host.recall();return true;}
        }
        if(!host.menuOpen()&&(code==KeyEvent.KEYCODE_INFO||code==KeyEvent.KEYCODE_MENU)){captured.add(code);if(event.getRepeatCount()==0)host.openMenu();return true;}
        if(center&&!host.menuOpen()){
            captured.add(code);
            if(host.live()){
                // Live: OK kurz = Banner (beim Loslassen), OK lang = Zahlenfeld.
                if(event.getRepeatCount()==0)longDone=false;
                else if(!longDone&&event.getEventTime()-event.getDownTime()>=500){longDone=true;host.numberPad();}
                return true;
            }
            if(event.getRepeatCount()==0)host.openMenu();return true;
        }
        if(captured.contains(code)&&center)return true;
        boolean channelKey=code==KeyEvent.KEYCODE_CHANNEL_UP||code==KeyEvent.KEYCODE_CHANNEL_DOWN;
        boolean mediaSeek=code==KeyEvent.KEYCODE_MEDIA_FAST_FORWARD||code==KeyEvent.KEYCODE_MEDIA_REWIND;
        if(host.menuOpen()&&!channelKey&&!mediaSeek)return false;
        if(host.live()&&(code==KeyEvent.KEYCODE_DPAD_LEFT||code==KeyEvent.KEYCODE_DPAD_RIGHT)){
            captured.add(code);long now=event.getEventTime();
            if(event.getRepeatCount()==0||lastGroup==Long.MIN_VALUE||now-lastGroup>=300){lastGroup=now;host.group(code==KeyEvent.KEYCODE_DPAD_RIGHT?1:-1);}
            return true;
        }
        int direction=0;
        if(host.live()){
            if(code==KeyEvent.KEYCODE_DPAD_UP||code==KeyEvent.KEYCODE_CHANNEL_UP)direction=1;
            if(code==KeyEvent.KEYCODE_DPAD_DOWN||code==KeyEvent.KEYCODE_CHANNEL_DOWN)direction=-1;
        }else{
            if(code==KeyEvent.KEYCODE_DPAD_RIGHT||code==KeyEvent.KEYCODE_MEDIA_FAST_FORWARD)direction=1;
            if(code==KeyEvent.KEYCODE_DPAD_LEFT||code==KeyEvent.KEYCODE_MEDIA_REWIND)direction=-1;
        }
        if(direction==0)return false;
        captured.add(code);
        long now=event.getEventTime();
        long interval=host.live()?300:150;
        if(event.getRepeatCount()==0||lastAction==Long.MIN_VALUE||now-lastAction>=interval){
            lastAction=now;
            if(host.live())host.channel(direction);
            else host.seek(direction*(event.getRepeatCount()>=5?30000L:10000L));
        }
        return true;
    }
    boolean motion(MotionEvent event){
        if(event.getAction()!=MotionEvent.ACTION_SCROLL||host.menuOpen())return false;
        float delta;
        if(event.isFromSource(InputDevice.SOURCE_ROTARY_ENCODER))delta=event.getAxisValue(MotionEvent.AXIS_SCROLL);
        else if(event.isFromSource(InputDevice.SOURCE_CLASS_POINTER)){
            float horizontal=event.getAxisValue(MotionEvent.AXIS_HSCROLL);
            delta=Math.abs(horizontal)>0?horizontal:event.getAxisValue(MotionEvent.AXIS_VSCROLL);
        }else return false;
        if(!Float.isFinite(delta)||delta==0)return false;
        if(Math.signum(scroll)!=Math.signum(delta))scroll=0;
        scroll+=delta;
        int steps=(int)Math.min(3,Math.abs(scroll));
        if(steps>0){
            int direction=scroll>0?1:-1;scroll=direction*(Math.abs(scroll)-(float)Math.floor(Math.abs(scroll)));
            // One channel per wheel event avoids overshooting many channels at once.
            if(host.live()){
                long now=event.getEventTime();if(lastAction==Long.MIN_VALUE||now-lastAction>=300){lastAction=now;host.channel(direction);}
                scroll=0;
            }else host.seek(direction*steps*10000L);
        }
        return true;
    }
    static long target(long position,long duration,long delta){
        long start=Math.max(0,position);
        long requested=delta>0&&start>Long.MAX_VALUE-delta?Long.MAX_VALUE:start+delta;
        long end=Math.max(0,requested);
        return duration>=0?Math.min(duration,end):end;
    }
}
