package ch.arjo.tv.android;

import static org.junit.Assert.*;

import java.util.Arrays;
import org.junit.Test;

public class PlaybackGuardTest {
    private static final String LIVE="http://anbieter.test:80/live/u/p/1.ts";
    private static final int CONNECTION=2001, PARSING=3001, BEHIND_LIVE=1002, NOT_FOUND=2005;

    @Test public void classifiesMedia3ErrorCodes(){
        assertEquals(PlaybackGuard.Kind.CONNECTION,PlaybackGuard.classify(CONNECTION));
        assertEquals(PlaybackGuard.Kind.CONNECTION,PlaybackGuard.classify(1000));
        assertEquals(PlaybackGuard.Kind.FORMAT,PlaybackGuard.classify(PARSING));
        assertEquals(PlaybackGuard.Kind.FORMAT,PlaybackGuard.classify(4003));
        assertEquals(PlaybackGuard.Kind.UNAVAILABLE,PlaybackGuard.classify(NOT_FOUND));
        assertEquals(PlaybackGuard.Kind.BEHIND_LIVE,PlaybackGuard.classify(BEHIND_LIVE));
    }
    @Test public void variantsOnlyForXtreamLive(){
        assertEquals(Arrays.asList("http://h.test:80/live/u/p/42.ts","http://h.test:80/live/u/p/42.m3u8"),PlaybackGuard.variants("http://h.test:80/u/p/42",""));
        assertEquals(Arrays.asList("http://h.test:80/live/u/p/42.m3u8","http://h.test:80/live/u/p/42.ts"),PlaybackGuard.variants("http://h.test:80/live/u/p/42.ts","m3u8"));
        assertEquals(Arrays.asList("https://cdn.test/a/index.m3u8"),PlaybackGuard.variants("https://cdn.test/a/index.m3u8",""));
    }
    @Test public void retriesTwiceAfterSixAndTwelveSecondsEvenIfEachAttemptStartsBriefly(){
        PlaybackGuard g=new PlaybackGuard();g.select(LIVE,true,"",0);
        long now=0;
        for(long expected:new long[]{6000,12000}){g.playing(now+=1000);PlaybackGuard.Decision d=g.error(CONNECTION,now+=1000);assertEquals(PlaybackGuard.Action.RETRY,d.action);assertEquals(expected,d.delayMs);}
        g.playing(now+=1000);
        assertEquals(PlaybackGuard.Action.GIVE_UP,g.error(CONNECTION,now+=1000).action);
    }
    @Test public void stablePlaybackResetsTheCounter(){
        PlaybackGuard g=new PlaybackGuard();g.select(LIVE,true,"",0);
        g.error(CONNECTION,1000);g.playing(8000);
        assertFalse(g.stable(20000));assertTrue(g.stable(38000));
        assertEquals(6000,g.error(CONNECTION,40000).delayMs);
    }
    @Test public void connectionErrorEnforcesFourSecondGapAlsoForTheNextChannel(){
        PlaybackGuard g=new PlaybackGuard();g.select(LIVE,true,"",0);g.playing(1000);
        g.error(CONNECTION,2000);g.closed(2000);
        assertEquals(3900,g.select("http://anbieter.test:80/live/u/p/2.ts",true,"",2100));
    }
    @Test public void formatFailureBeforeFirstPictureTriesHlsOnceThenGivesUp(){
        PlaybackGuard g=new PlaybackGuard();g.select(LIVE,true,"",0);
        assertTrue(g.url().endsWith(".ts"));
        assertEquals(PlaybackGuard.Action.VARIANT,g.error(PARSING,1000).action);
        assertTrue(g.url().endsWith(".m3u8"));
        assertEquals(PlaybackGuard.Action.GIVE_UP,g.error(PARSING,2000).action);
    }
    @Test public void formatFailureAfterFirstPictureDoesNotSwitchFormat(){
        PlaybackGuard g=new PlaybackGuard();g.select(LIVE,true,"",0);g.playing(1000);
        assertEquals(PlaybackGuard.Action.GIVE_UP,g.error(PARSING,2000).action);
        assertTrue(g.url().endsWith(".ts"));
    }
    @Test public void behindLiveWindowReprepares(){
        PlaybackGuard g=new PlaybackGuard();g.select(LIVE,true,"",0);
        assertEquals(PlaybackGuard.Action.REPREPARE,g.error(BEHIND_LIVE,1000).action);
    }
    @Test public void stallRecoversAtMostTwiceInTenMinutesAndNotWhilePausedOrForVod(){
        PlaybackGuard g=new PlaybackGuard();g.select(LIVE,true,"",0);g.playing(1000);
        g.buffering(2000);
        assertFalse(g.stalled(21000,true));
        assertFalse("pausiert",g.stalled(30000,false));
        assertTrue(g.stalled(30000,true));
        g.buffering(31000);assertTrue(g.stalled(52000,true));
        g.buffering(53000);assertFalse(g.stalled(80000,true));assertTrue(g.stallGiveUp(80000,true));
        PlaybackGuard vod=new PlaybackGuard();vod.select("http://h.test/movie/u/p/5.mkv",false,"",0);vod.playing(1000);vod.buffering(2000);
        assertFalse(vod.stalled(60000,true));
    }
    @Test public void rapidZappingWaitsForQuiet(){
        PlaybackGuard g=new PlaybackGuard();
        assertEquals(0,g.select(LIVE,true,"",10000));
        assertEquals(PlaybackGuard.ZAP_GAP_MS,g.select("http://anbieter.test:80/live/u/p/2.ts",true,"",10300));
        assertEquals(0,g.select("http://anbieter.test:80/live/u/p/3.ts",true,"",20000));
    }
    @Test public void preferredFormatIsUsedFirst(){
        PlaybackGuard g=new PlaybackGuard();g.select(LIVE,true,"m3u8",0);
        assertTrue(g.url().endsWith("1.m3u8"));
    }
}
