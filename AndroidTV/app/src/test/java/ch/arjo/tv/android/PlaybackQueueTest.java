package ch.arjo.tv.android;

import org.junit.Test;
import java.util.*;
import static org.junit.Assert.*;

public class PlaybackQueueTest {
    private Entry entry(String id,String group,String kind){return new Entry(id,id,group,"https://example.test/"+id+".ts",kind);}
    @Test public void queueUsesCurrentGroupInCatalogueOrderAndWraps(){Entry a=entry("a","CH","live"),b=entry("b","CH","live"),other=entry("c","DE","live"),film=entry("d","CH","movie");PlaybackQueue queue=new PlaybackQueue(Arrays.asList(a,other,film,b,b),a,"scope");assertEquals(2,queue.size());assertEquals("b",queue.move(1).id);assertEquals("a",queue.move(1).id);assertEquals("b",queue.move(-1).id);}
    @Test public void absentOrSingleChannelStillHasValidSelection(){Entry a=entry("a","CH","live");PlaybackQueue queue=new PlaybackQueue(Collections.emptyList(),a,"scope");assertEquals(1,queue.size());assertSame(a,queue.current());assertSame(a,queue.move(1));}
    @Test public void restoredSelectionDoesNotRestartAtFirstChannel(){Entry a=entry("a","CH","live"),b=entry("b","CH","live");PlaybackQueue queue=new PlaybackQueue(Arrays.asList(a,b),a,"scope");queue.select("b");assertSame(b,queue.current());}
    @Test public void sessionTokensAvoidLargeIntentsAndOldSessionsDoNotResolve(){Entry a=entry("a","CH","live");PlaybackQueue first=new PlaybackQueue(Collections.emptyList(),a,"scope");String old=PlaybackQueue.register(first);assertSame(first,PlaybackQueue.get(old));String current=PlaybackQueue.register(first);assertNull(PlaybackQueue.get(old));PlaybackQueue.clear(old);assertSame(first,PlaybackQueue.get(current));PlaybackQueue.clear(current);assertNull(PlaybackQueue.get(current));}
}
