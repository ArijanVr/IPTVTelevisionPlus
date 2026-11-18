package ch.arjo.tv.android;

import android.content.SharedPreferences;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.Config;
import java.util.*;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=28)
public class ListsTest {
    private SharedPreferences prefs;
    private final Entry a=new Entry("live:1","SRF 1","Schweiz","https://example.test/1.ts","live"),b=new Entry("live:2","Arte","Doku","https://example.test/2.ts","live"),film=new Entry("movie:1","Film","Doku","https://example.test/m.mp4","movie");
    @Before public void setup(){prefs=RuntimeEnvironment.getApplication().getSharedPreferences("lists-test",0);prefs.edit().clear().commit();}
    @Test public void hidingChannelsAndGroupsIsPerAreaAndPerSource(){
        Lists lists=new Lists(prefs,"quelle-1");
        lists.setHidden(a,true);assertEquals(Arrays.asList(b,film),lists.visible(Arrays.asList(a,b,film)));
        lists.setGroupHidden("live","Doku",true);assertEquals("Filme mit gleicher Gruppe bleiben",Collections.singletonList(film),lists.visible(Arrays.asList(a,b,film)));
        assertTrue(new Lists(prefs,"quelle-2").visible(Arrays.asList(a,b)).size()==2);
        lists.setHidden(a,false);lists.setGroupHidden("live","Doku",false);assertEquals(3,lists.visible(Arrays.asList(a,b,film)).size());
    }
    @Test public void renamingAndResettingNames(){
        Lists lists=new Lists(prefs,"q");lists.rename(a,"  Schweiz 1 ");assertEquals("Schweiz 1",lists.name(a));lists.rename(a,"");assertEquals("SRF 1",lists.name(a));
        lists.renameGroup("live","Doku","Wissen");assertEquals("Wissen",lists.groupName("live","Doku"));assertEquals("Doku",lists.groupName("movie","Doku"));
    }
    @Test public void groupOrderKeepsUnknownGroupsInProviderOrder(){
        Lists lists=new Lists(prefs,"q");List<String> groups=Arrays.asList("A","B","C","D");
        lists.move("live",groups,"C",-2);assertEquals(Arrays.asList("C","A","B","D"),lists.ordered("live",groups));
        lists.move("live",groups,"C",-1);assertEquals("oben angekommen",Arrays.asList("C","A","B","D"),lists.ordered("live",groups));
        assertEquals(Arrays.asList("C","A","B","D","E"),lists.ordered("live",Arrays.asList("A","B","C","D","E")));
        assertEquals(groups,lists.ordered("movie",groups));lists.resetOrder("live");assertEquals(groups,lists.ordered("live",groups));
    }
    @Test public void homeSectionsAndTilesCanBeArranged(){
        Lists lists=new Lists(prefs,"q");assertEquals(Arrays.asList(Lists.SECTIONS),lists.visibleSections());
        lists.moveSection("favorites",-3);lists.setSectionHidden("hero",true);
        assertEquals("favorites",lists.visibleSections().get(0));assertFalse(lists.visibleSections().contains("hero"));
        lists.resetHome();assertEquals(Arrays.asList(Lists.SECTIONS),lists.visibleSections());
        assertTrue(lists.showNames());lists.setShowNames(false);assertFalse(new Lists(prefs,"andere").showNames());
        lists.setTileSize(9);assertEquals(2,lists.tileSize());assertEquals(236,lists.tileWidth());
    }
}
