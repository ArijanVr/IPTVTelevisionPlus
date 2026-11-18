package ch.arjo.tv.android;

import android.app.Activity;
import android.graphics.*;
import android.os.Looper;
import android.view.*;
import android.widget.*;
import androidx.recyclerview.widget.RecyclerView;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.*;
import java.io.*;
import java.util.*;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=28,qualifiers="w960dp-h540dp-land-mdpi")
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class LibraryViewTest {
    private ActivityController<Activity> controller;
    private Activity activity;
    private LibraryView view;
    private Artwork artwork;
    private String navigated,opened,played,menu,lastAction;
    private final List<Entry> fixture=new ArrayList<>();
    @Before public void setup(){
        controller=Robolectric.buildActivity(Activity.class).setup();activity=controller.get();artwork=new Artwork();
        // Robolectric starts in touch mode; an actual TV D-pad leaves touch mode.
        Object root=org.robolectric.util.ReflectionHelpers.callInstanceMethod(activity.getWindow().getDecorView(),"getViewRootImpl");
        org.robolectric.util.ReflectionHelpers.callInstanceMethod(root,"ensureTouchMode",org.robolectric.util.ReflectionHelpers.ClassParameter.from(boolean.class,false));
        for(int i=1;i<=12;i++)fixture.add(new Entry("live:"+i,"Testsender "+i,i<7?"Schweiz":"International","https://example.test/live/"+i+".ts","live"));
        for(int i=1;i<=8;i++)fixture.add(new Entry("movie:"+i,"Filmbeispiel "+i,"Spielfilme","https://example.test/movie/"+i+".mp4","movie","","2026 · ★ 8.0"));
        fixture.add(new Entry("series:1","Serienbeispiel","Serien","","series","","2026"));
        view=new LibraryView(activity,artwork,new LibraryView.Actions(){
            public void navigate(String kind){navigated=kind;}
            public void open(Entry e){opened=e.id;}
            public void play(Entry e){played=e.id;}
            public void menu(Entry e){menu=e.id;}
            public void search(String query){view.filter(query);}
            public void action(String action){lastAction=action;}
        },new LibraryView.Progress(){public long position(Entry e){return e.id.equals("movie:1")?120000:0;}public float fraction(Entry e){return e.id.equals("movie:1")?.35f:0;}});
        activity.setContentView(view);view.activate("home");view.setData(fixture,new HashSet<>(Arrays.asList("live:1","live:2")),Arrays.asList(fixture.get(12),fixture.get(0)));layout();
    }
    @After public void close(){artwork.close();controller.close();}
    private void layout(){Shadows.shadowOf(Looper.getMainLooper()).idle();view.measure(View.MeasureSpec.makeMeasureSpec(960,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(540,View.MeasureSpec.EXACTLY));view.layout(0,0,960,540);Shadows.shadowOf(Looper.getMainLooper()).idle();}
    private TextView text(View root,String value){
        if(root instanceof TextView && ((TextView)root).getText().toString().equals(value))return (TextView)root;
        if(root instanceof ViewGroup)for(int i=0;i<((ViewGroup)root).getChildCount();i++){TextView hit=text(((ViewGroup)root).getChildAt(i),value);if(hit!=null)return hit;}return null;
    }
    private View described(View root,String value){
        if(value.contentEquals(root.getContentDescription()==null?"":root.getContentDescription()))return root;
        if(root instanceof ViewGroup)for(int i=0;i<((ViewGroup)root).getChildCount();i++){View hit=described(((ViewGroup)root).getChildAt(i),value);if(hit!=null)return hit;}return null;
    }
    private void snapshot(String name)throws Exception{
        layout();Bitmap bitmap=Bitmap.createBitmap(960,540,Bitmap.Config.ARGB_8888);view.draw(new Canvas(bitmap));File folder=new File("build/previews");assertTrue(folder.isDirectory()||folder.mkdirs());try(FileOutputStream out=new FileOutputStream(new File(folder,name+".png"))){assertTrue(bitmap.compress(Bitmap.CompressFormat.PNG,100,out));}
    }
    @Test public void homeUsesOriginalHierarchyAndSixNavigationDestinations()throws Exception{
        assertNotNull(text(view,"Jetzt"));assertNotNull(text(view,"Live"));assertNotNull(text(view,"Mediathek"));assertNotNull(text(view,"Filme"));assertNotNull(text(view,"Serien"));assertNotNull(text(view,"Suche"));assertNotNull(text(view,"Profil"));
        assertNotNull(text(view,"WEITERSCHAUEN"));assertNotNull(text(view,"Filmbeispiel 1"));
        text(view,"▶ Fortsetzen").performClick();assertEquals("movie:1",played);snapshot("Startseite");
    }
    @Test public void liveCardsAreRemoteFocusableAndHaveFavoriteMenu()throws Exception{
        view.activate("live");view.setData(fixture.subList(0,12),Collections.singleton("live:1"),Collections.emptyList());layout();
        View first=described(view,"Testsender 1, Favorit");assertNotNull(first);assertTrue("Card must be focusable",first.isFocusable());assertTrue("Request focus, touch mode="+first.isInTouchMode(),first.requestFocus());assertTrue("Card must hold focus",first.hasFocus());
        first.performClick();assertEquals("live:1",opened);first.performLongClick();assertEquals("live:1",menu);
        View next=first.focusSearch(View.FOCUS_RIGHT);assertNotNull(next);next.requestFocus();assertTrue(next.hasFocus());assertNotSame(first,next);snapshot("Live-TV");
        text(view,"Kategorien").performClick();layout();assertNotNull(described(view,"Schweiz, 6"));assertNotNull(described(view,"International, 6"));assertNotNull(text(view,"Live · Kategorien"));snapshot("Kategorien");
    }
    @Test public void moviePostersAndDetailActionsMatchOriginalFlow()throws Exception{
        view.activate("movie");view.setData(fixture.subList(12,20),Collections.emptySet(),Collections.emptyList());layout();assertNotNull(described(view,"Filmbeispiel 1"));snapshot("Filme");
        Entry film=fixture.get(12);view.showDetail(film);view.detailInfo(film,new org.json.JSONObject("{\"info\":{\"genre\":\"Drama\",\"plot\":\"Beispiel einer vom Anbieter gelieferten Beschreibung.\",\"cast\":\"Beispielbesetzung\"}}"));layout();assertTrue(view.hasDetail());assertNotNull(text(view,"▶ Fortsetzen"));text(view,"▶ Fortsetzen").performClick();assertEquals(film.id,played);snapshot("Filmdetails");view.closeDetail();assertFalse(view.hasDetail());
    }
    @Test public void searchFiltersAndNavigationDoesNotPlayOnFocus(){
        view.activate("search");view.setData(fixture,Collections.emptySet(),Collections.emptyList());view.filter("Filmbeispiel 7");layout();assertNotNull(described(view,"Filmbeispiel 7"));assertNull(described(view,"Filmbeispiel 1"));
        TextView nav=text(view,"Serien");nav.requestFocus();assertNull(navigated);assertNull(played);nav.performClick();assertEquals("series",navigated);
    }
    @Test public void menuBandIsCenteredOnTheEntireScreenAtBothWidths(){
        View band=view.findViewWithTag("main_navigation");assertNotNull(band);
        for(int width:new int[]{960,1280}){
            view.measure(View.MeasureSpec.makeMeasureSpec(width,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(540,View.MeasureSpec.EXACTLY));view.layout(0,0,width,540);
            android.graphics.Rect bounds=new android.graphics.Rect(0,0,band.getWidth(),band.getHeight());view.offsetDescendantRectToMyCoords(band,bounds);
            assertEquals("Menu must be centered independently of the left brand",width/2f,bounds.exactCenterX(),.5f);
        }
    }
    @Test public void changingToolbarModeKeepsItsRemoteFocus() {
        view.activate("live");view.setData(fixture.subList(0,12),Collections.emptySet(),Collections.emptyList());layout();
        TextView category=text(view,"Kategorien");assertTrue(category.requestFocus());category.performClick();layout();
        assertTrue("Toolbar focus must survive mode change",text(view,"Kategorien").hasFocus());
    }
    @Test public void logoTilesHonourHiddenNamesCustomOrderAndHomeLayout()throws Exception{
        Lists lists=new Lists(activity.getSharedPreferences("library",0),"fixture");lists.setShowNames(false);lists.renameGroup("live","International","Welt");lists.move("live",Arrays.asList("Schweiz","International"),"International",-1);lists.rename(fixture.get(0),"Mein Sender");
        view.setLists(lists);view.activate("live");view.setData(fixture.subList(0,12),Collections.emptySet(),Collections.emptyList());layout();
        View tile=described(view,"Mein Sender");assertNotNull("Eigener Name",tile);TextView name=text(view,"Mein Sender");assertTrue("Ohne Namen unter der Kachel",name==null||name.getVisibility()!=View.VISIBLE);
        assertTrue(tile.requestFocus());layout();assertEquals("Name erscheint bei Fokus",View.VISIBLE,text(view,"Mein Sender").getVisibility());
        TextView world=text(view,"Welt"),swiss=text(view,"Schweiz");assertNotNull(world);int[] w=new int[2],c=new int[2];world.getLocationInWindow(w);
        if(swiss!=null){swiss.getLocationInWindow(c);assertTrue("Eigene Reihenfolge: Welt vor Schweiz",w[1]<c[1]);}snapshot("Live-TV-ohne-Namen");
        lists.setSectionHidden("hero",true);view.activate("home");view.setData(fixture,new HashSet<>(Collections.singletonList("live:2")),Collections.emptyList());layout();assertNull(text(view,"FAVORIT"));assertNotNull(text(view,"Favoriten"));
    }
    @Test public void listEditorTogglesVisibilityAndClosesLikeADetail()throws Exception{
        Lists lists=new Lists(activity.getSharedPreferences("library",0),"editor");List<String> changes=new ArrayList<>();
        ListEditor editor=new ListEditor(activity,lists,"categories",new ListEditor.Host(){
            public List<Entry> all(){return fixture;} public Set<String> favorites(){return Collections.emptySet();} public void toggleFavorite(Entry e){}
            public void changed(){changes.add("x");} public void close(){view.closeDetail();}
        });
        view.showPanel(editor);layout();assertTrue(view.hasDetail());assertNotNull(described(view,"Schweiz, Sichtbar"));
        described(view,"Schweiz, Sichtbar").performClick();layout();assertTrue(lists.groupHidden("live","Schweiz"));assertNotNull(described(view,"Schweiz, Ausgeblendet"));assertEquals(1,changes.size());snapshot("Meine-Listen");
        text(editor,"Jetzt").performClick();layout();described(view,"Sendernamen unter den Kacheln, Ein").performClick();assertFalse(lists.showNames());
        view.closeDetail();assertFalse(view.hasDetail());
    }
    @Test public void seriesPresentsStaffelPickerAndEpisodes()throws Exception{
        Entry series=fixture.get(20);view.showDetail(series);view.detailInfo(series,new org.json.JSONObject("{\"info\":{\"plot\":\"Eine Beispielserie aus der Testquelle.\"}}"));view.episodes(series,Arrays.asList(new Entry("episode:1","Episode 1","Staffel 1","https://example.test/1.mp4","episode"),new Entry("episode:2","Episode 2","Staffel 1","https://example.test/2.mp4","episode")));layout();assertNotNull(text(view,"Staffel 1 ⌄"));snapshot("Seriendetails");
    }
    @Test public void movieCategoriesListDrivesThePosterGridAndTheDpadMovesBetweenThem()throws Exception{
        List<Entry> films=new ArrayList<>();
        for(int i=1;i<=4;i++)films.add(new Entry("movie:a"+i,"Actionfilm "+i,"Action","https://example.test/a"+i+".mp4","movie","","2026"));
        for(int i=1;i<=4;i++)films.add(new Entry("movie:d"+i,"Dramafilm "+i,"Drama","https://example.test/d"+i+".mp4","movie","","2026"));
        view.activate("movie");view.setData(films,Collections.emptySet(),Collections.emptyList());layout();
        assertNotNull(text(view,"Filme · Kategorien"));
        View all=described(view,"Alle, 8"),drama=described(view,"Drama, 4");assertNotNull(all);assertNotNull(drama);assertNotNull(described(view,"Actionfilm 1"));
        assertTrue(drama.requestFocus());
        Shadows.shadowOf(Looper.getMainLooper()).idleFor(java.time.Duration.ofMillis(400));layout();
        assertNotNull("Raster zeigt die fokussierte Kategorie",described(view,"Dramafilm 1"));assertNull(described(view,"Actionfilm 1"));
        drama.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_RIGHT));layout();Shadows.shadowOf(Looper.getMainLooper()).idle();
        View focused=view.findFocus();assertNotNull(focused);assertEquals("Dramafilm 1",String.valueOf(focused.getContentDescription()));
        focused.performClick();assertEquals("movie:d1",opened);
        focused.dispatchKeyEvent(new KeyEvent(KeyEvent.ACTION_DOWN,KeyEvent.KEYCODE_DPAD_LEFT));layout();
        assertTrue("Links zurück in die Liste",view.findFocus()==drama||"Drama, 4".contentEquals(String.valueOf(view.findFocus().getContentDescription())));
        snapshot("Filme-Kategorien");
    }
    @Test public void settingsAreATileGridThatOpensTheExistingAreas()throws Exception{
        view.activate("settings");view.setData(fixture,Collections.emptySet(),Collections.emptyList());layout();
        String[][] tiles={{"Quellen","sources"},{"Meine Listen","lists"},{"Darstellung","lists:home"},{"Wiedergabe","playback"},{"Kanalnummern","numbers"},{"Über IP Television+","info"}};
        for(String[] t:tiles){View tile=null;for(String sub:new String[]{"Zugang neu laden, wechseln oder entfernen","Kategorien, Sender und Startseite ordnen","Kachelgrösse und Sendernamen","Start, Kanal und Multiview","So wählst Du Sender per Zahl","Version, Funktionen und Hinweise"}){View hit=described(view,t[0]+", "+sub);if(hit!=null)tile=hit;}
            assertNotNull("Kachel "+t[0],tile);assertTrue(tile.isFocusable());lastAction=null;tile.performClick();assertEquals(t[1],lastAction);}
        assertNotNull(described(view,"Ein Produkt von ARJO LAB"));snapshot("Einstellungen");
    }
}
