package ch.arjo.tv.android;

import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;
import java.io.StringReader;
import java.nio.charset.StandardCharsets;
import java.util.*;
import okhttp3.mockwebserver.*;

import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=28, manifest=Config.NONE)
public class CatalogTest {
    @Test public void credentialsAreEncodedInQueryAndPath() {
        Source s=new Source("xtream","https://example.test:8080/path","user +&","test /+&?");
        assertEquals("https://example.test:8080/player_api.php?username=user%20%2B%26&password=test%20%2F%2B%26%3F&action=get_live_streams",s.api("get_live_streams"));
        assertEquals("https://example.test:8080/live/user%20%2B%26/test%20%2F%2B%26%3F/12.ts",s.stream("live","12","ts"));
    }
    @Test public void sourceIdentityIgnoresXtreamPasswordRotation() {
        assertEquals(new Source("xtream","https://example.test","user","one").scope(),new Source("xtream","https://example.test/","user","two").scope());
        assertNotEquals(new Source("xtream","https://example.test","user","one").scope(),new Source("xtream","https://example.test","other","one").scope());
    }
    @Test public void rejectsInvalidOrEmbeddedCredentials() {
        for (String url:new String[]{"file:///etc/passwd","javascript:alert(1)","https://user:pass@example.test","not a url","https://example.test/#secret"}) {
            try { new Source("m3u",url,"",""); fail("Must reject invalid address"); } catch (IllegalArgumentException expected) { }
        }
    }
    @Test public void playlistHandlesBomQuotedCommasRelativeUrlsAndTypes() throws Exception {
        String fixture="\uFEFF#EXTM3U\n#EXTINF:-1 tvg-name=\"News\" group-title=\"Schweiz, DE\",News, HD\n/live/1.ts\n"
            +"#EXTINF:-1 group-title=\"Kino\",Film\n/movie/2.mkv\n"
            +"#EXTINF:-1,Show S01E02\n/series/3.mp4\n#EXTINF:-1,Bad\nfile:///bad\n";
        List<Entry> rows=M3u.parse(new StringReader(fixture),"https://example.test/list.m3u");
        assertEquals(3,rows.size()); assertEquals("News, HD",rows.get(0).name); assertEquals("Schweiz, DE",rows.get(0).group);
        assertEquals("https://example.test/live/1.ts",rows.get(0).url); assertEquals("live",rows.get(0).kind);
        assertEquals("movie",rows.get(1).kind); assertEquals("episode",rows.get(2).kind);
    }
    @Test public void playlistResetsMetadataAndAcceptsExtgrp() throws Exception {
        List<Entry> rows=M3u.parse(new StringReader("#EXTM3U\n#EXTINF:-1,First\n#EXTGRP:Sport\nhttps://example.test/1\nhttps://example.test/2\n"),"https://example.test/list");
        assertEquals("Sport",rows.get(0).group); assertEquals("Ohne Gruppe",rows.get(1).group); assertEquals("Eintrag 2",rows.get(1).name);
    }
    @Test public void playlistArtworkIsResolvedAndNeverBleedsIntoNextEntry() throws Exception {
        List<Entry> list=M3u.parse(new StringReader("#EXTM3U\n#EXTINF:-1 tvg-logo=\"/logo.png\",Sender\n/stream.ts\n#EXTINF:-1,Anderer\n/other.ts\n"),"https://example.test/playlist.m3u");
        assertEquals("https://example.test/logo.png",list.get(0).image);assertEquals("",list.get(1).image);
    }
    private MockWebServer server;
    private boolean reject;
    @Before public void start() throws Exception {
        server=new MockWebServer();
        server.setDispatcher(new Dispatcher() { @Override public MockResponse dispatch(RecordedRequest request) {
            if (reject) return new MockResponse().setResponseCode(403);
            String query=request.getPath(); String body;
            if (query.contains("action=get_live_categories")) body="[{\"category_id\":1,\"category_name\":\"Schweiz\"}]";
            else if (query.contains("action=get_live_streams")) body="[{\"stream_id\":42,\"name\":\"Testkanal\",\"category_id\":\"1\"},{\"stream_id\":\"../bad\"}]";
            else if (query.contains("action=get_series_info")) body="{\"episodes\":{\"10\":[{\"id\":7,\"episode_num\":1,\"title\":\"Finale\",\"container_extension\":\"mkv\"}],\"2\":[{\"id\":5,\"episode_num\":2},{\"id\":4,\"episode_num\":1}]}}";
            else body="{\"user_info\":{\"auth\":1,\"status\":\"Active\"}}";
            return new MockResponse().setBody(body);
        }}); server.start();
    }
    @After public void stop() throws Exception { server.shutdown(); }
    private Source local() { return new Source("xtream",server.url("/").toString(),"fixture","fixture"); }
    @Test public void xtreamAuthenticatesMapsMixedIdsAndBuildsStreams() throws Exception {
        Catalog c=new Catalog(local()); c.authenticate(); List<Entry> list=c.load("live");
        assertEquals(1,list.size()); assertEquals("Schweiz",list.get(0).group); assertTrue(list.get(0).url.endsWith("/live/fixture/fixture/42.ts"));
    }
    @Test public void episodesSortSeasonsAndEpisodeNumbersNumerically() throws Exception {
        List<Entry> list=new Catalog(local()).episodes(new Entry("series:9","Testserie","Series","","series"));
        assertEquals(3,list.size()); assertEquals("episode:4",list.get(0).id); assertEquals("episode:5",list.get(1).id);
        assertEquals("Staffel 10",list.get(2).group); assertTrue(list.get(2).url.endsWith("/series/fixture/fixture/7.mkv"));
    }
    @Test public void serverErrorsAreReportedWithoutUrlsOrCredentials() throws Exception {
        reject=true;
        try { new Catalog(local()).authenticate(); fail("Must reject 403"); }
        catch (java.io.IOException expected) { assertFalse(expected.getMessage().contains("fixture")); assertFalse(expected.getMessage().contains("http")); }
    }
}
