package ch.arjo.tv.android;

import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import java.io.File;
import java.nio.file.Files;
import java.util.*;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=28)
public class CatalogCacheTest {
    private final byte[] key=new byte[32];
    private CatalogCache cache;
    private List<Entry> entries;
    @Before public void setup(){
        Arrays.fill(key,(byte)7);cache=new CatalogCache(RuntimeEnvironment.getApplication(),()->key);cache.clear();
        entries=new ArrayList<>();for(int i=0;i<500;i++)entries.add(new Entry("live:"+i,"Sender \"é\" "+i,"Gruppe","https://example.test/live/u/p/"+i+".ts","live","https://example.test/l"+i+".png","Sub").withNumber(i+1).withSourceNumber(i%3));
    }
    @Test public void roundTripKeepsAllFields(){
        cache.save("scope","playlist",entries);
        CatalogCache.Hit hit=cache.load("scope","playlist");
        assertNotNull(hit);assertEquals(500,hit.entries.size());assertFalse(hit.stale());
        Entry e=hit.entries.get(42);assertEquals("live:42",e.id);assertEquals("Sender \"é\" 42",e.name);assertEquals("Gruppe",e.group);assertEquals("https://example.test/live/u/p/42.ts",e.url);
        assertEquals("live",e.kind);assertEquals("https://example.test/l42.png",e.image);assertEquals("Sub",e.subtitle);assertEquals(43,e.number);assertEquals(0,e.sourceNumber);assertEquals(1,hit.entries.get(43).sourceNumber);
    }
    @Test public void fileDoesNotContainReadableStreamUrls() throws Exception{
        cache.save("scope","playlist",entries);
        File dir=new File(RuntimeEnvironment.getApplication().getCacheDir(),"catalog");File[] files=dir.listFiles((d,n)->n.endsWith(".bin"));
        assertEquals(1,files.length);assertFalse(new String(Files.readAllBytes(files[0].toPath()),"ISO-8859-1").contains("example.test"));
    }
    @Test public void missingScopeOrKeyGivesNothing(){
        cache.save("scope","playlist",entries);
        assertNull(cache.load("andere","playlist"));assertNull(cache.load("scope","live"));
    }
    @Test public void wrongKeyOrDamagedFileIsDroppedAndNeverThrows(){
        cache.save("scope","playlist",entries);
        byte[] other=new byte[32];assertNull(new CatalogCache(RuntimeEnvironment.getApplication(),()->other).load("scope","playlist"));
        assertNull("beschädigte Datei wird entfernt",cache.load("scope","playlist"));
        cache.save("scope","playlist",entries);
        File dir=new File(RuntimeEnvironment.getApplication().getCacheDir(),"catalog");File f=dir.listFiles((d,n)->n.endsWith(".bin"))[0];
        try{try(java.io.RandomAccessFile r=new java.io.RandomAccessFile(f,"rw")){r.seek(40);r.write(new byte[]{1,2,3,4});}}catch(Exception e){fail();}
        assertNull(cache.load("scope","playlist"));assertFalse(f.exists());
    }
    @Test public void keyFailureNeverThrows(){
        CatalogCache broken=new CatalogCache(RuntimeEnvironment.getApplication(),()->{throw new Exception("kein Schlüssel");});
        broken.save("scope","playlist",entries);assertNull(broken.load("scope","playlist"));
    }
    @Test public void staleAfterSixHours() throws Exception{
        cache.save("scope","playlist",entries);CatalogCache.Hit hit=cache.load("scope","playlist");
        assertTrue(new CatalogCache.Hit(hit.entries,System.currentTimeMillis()-7L*3600*1000).stale());assertFalse(new CatalogCache.Hit(hit.entries,System.currentTimeMillis()-5L*3600*1000).stale());
    }
    @Test public void clearRemovesEverything(){
        cache.save("a","playlist",entries);cache.save("b","live",entries);cache.clear();assertNull(cache.load("a","playlist"));assertNull(cache.load("b","live"));
    }
}
