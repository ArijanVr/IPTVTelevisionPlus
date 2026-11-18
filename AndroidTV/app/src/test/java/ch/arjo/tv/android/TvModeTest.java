package ch.arjo.tv.android;

import android.view.KeyEvent;
import java.util.*;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=28,manifest=Config.NONE)
public class TvModeTest {
    private static Entry live(String id,String group,int number){return new Entry(id,id,group,"https://example.test/"+id+".ts","live").withNumber(number);}

    private static class Host implements RemoteInput.Host {
        boolean live=true,menu,pending;int channels,groups,infos,pads,recalls,commits;final List<Integer> digits=new ArrayList<>();
        public boolean live(){return live;}public boolean menuOpen(){return menu;}
        public void channel(int d){channels+=d;}public void seek(long d){}public void openMenu(){menu=true;}
        public void group(int d){groups+=d;}public void digit(int d){digits.add(d);pending=true;}public void commit(){commits++;pending=false;}
        public boolean pendingDigits(){return pending;}public void info(){infos++;}public void numberPad(){pads++;}public void recall(){recalls++;}
    }
    private final Host host=new Host();
    private final RemoteInput input=new RemoteInput(host);
    private KeyEvent key(int action,int code,long down,long time,int repeat){return new KeyEvent(down,time,action,code,repeat);}
    private void tap(int code){assertTrue(input.key(key(KeyEvent.ACTION_DOWN,code,10,10,0)));assertTrue(input.key(key(KeyEvent.ACTION_UP,code,10,20,0)));}

    @Test public void digitKeysEnterNumbersInLiveOnly(){
        tap(KeyEvent.KEYCODE_1);tap(KeyEvent.KEYCODE_NUMPAD_2);
        assertEquals(Arrays.asList(1,2),host.digits);
        Host film=new Host();film.live=false;RemoteInput filmInput=new RemoteInput(film);
        assertFalse(filmInput.key(key(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_3,10,10,0)));assertTrue(film.digits.isEmpty());
    }
    @Test public void leftRightSwitchGroupsInLiveAndUpDownStillChangesChannel(){
        tap(KeyEvent.KEYCODE_DPAD_RIGHT);tap(KeyEvent.KEYCODE_DPAD_LEFT);tap(KeyEvent.KEYCODE_DPAD_RIGHT);
        assertEquals(1,host.groups);tap(KeyEvent.KEYCODE_DPAD_UP);assertEquals(1,host.channels);
    }
    @Test public void shortOkShowsBannerLongOkOpensNumberPad(){
        tap(KeyEvent.KEYCODE_DPAD_CENTER);assertEquals(1,host.infos);assertEquals(0,host.pads);assertFalse(host.menu);
        input.key(key(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_CENTER,100,100,0));
        input.key(key(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_CENTER,100,700,1));
        input.key(key(KeyEvent.ACTION_UP,KeyEvent.KEYCODE_DPAD_CENTER,100,720,0));
        assertEquals(1,host.pads);assertEquals(1,host.infos);
    }
    @Test public void okWithPendingDigitsCommitsImmediately(){tap(KeyEvent.KEYCODE_4);tap(KeyEvent.KEYCODE_DPAD_CENTER);assertEquals(1,host.commits);assertEquals(0,host.infos);}
    @Test public void infoKeyOpensTrackMenu(){tap(KeyEvent.KEYCODE_INFO);assertTrue(host.menu);}
    @Test public void lastChannelKeyRecalls(){tap(KeyEvent.KEYCODE_LAST_CHANNEL);assertEquals(1,host.recalls);}

    @Test public void queueStartsGroupAtLowestNumberAndJumpsGlobally(){
        List<Entry> all=Arrays.asList(live("a","Schweiz",3),live("b","Schweiz",1),live("c","Sport",20),live("d","Sport",10));
        PlaybackQueue queue=new PlaybackQueue(all,all.get(0),"scope",Arrays.asList("Schweiz","Sport"));
        assertEquals(Arrays.asList("Schweiz","Sport"),queue.groups());
        assertEquals("b",queue.move(-1).id);assertEquals("a",queue.move(-1).id);
        ChannelNavigator.GroupPosition next=queue.neighbourGroup("Schweiz",1);
        assertEquals(new ChannelNavigator.GroupPosition("Sport",2,2),next);
        assertEquals("d",queue.startGroup("Sport").id);
        assertEquals("b",queue.jump(queue.byNumber(1)).id);
        assertNull(queue.byNumber(99));
        assertEquals("d",queue.previous().id);
        assertEquals("b",queue.first().id);
    }
    @Test public void numberStoreKeepsNumbersAcrossReloads(){
        android.content.SharedPreferences prefs=org.robolectric.RuntimeEnvironment.getApplication().getSharedPreferences("t",0);
        List<Entry> first=Arrays.asList(live("a","G",0),live("b","G",0));
        NumberStore.apply(prefs,"s",first,true);assertEquals(1,first.get(0).number);assertEquals(2,first.get(1).number);
        List<Entry> second=Arrays.asList(live("n","G",0),live("b","G",0),live("a","G",0));
        NumberStore.apply(prefs,"s",second,true);
        assertEquals(3,second.get(0).number);assertEquals(2,second.get(1).number);assertEquals(1,second.get(2).number);
    }
}
