package ch.arjo.tv.android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import org.junit.Test;
import org.junit.runner.RunWith;
import org.robolectric.RobolectricTestRunner;
import org.robolectric.annotation.Config;

@RunWith(RobolectricTestRunner.class)
@Config(sdk = 35)
public class UpdaterTest {
    @Test public void comparesVersions() {
        assertTrue(Updater.isNewer("v1.1.2", "1.1.1"));
        assertTrue(Updater.isNewer("1.10", "1.9.9"));
        assertFalse(Updater.isNewer("1.1.1", "1.1.1"));
        assertFalse(Updater.isNewer("1.1", "1.1.0"));
        assertFalse(Updater.isNewer("v1.0.9", "1.1.0"));
    }

    @Test public void picksGoogleTvApk() throws Exception {
        String json = "{\"tag_name\":\"v1.2.0\",\"body\":\"Neu\",\"assets\":["
            + "{\"name\":\"IPTelevisionPlus-1.2.0-macOS.dmg\",\"browser_download_url\":\"https://x/dmg\"},"
            + "{\"name\":\"IPTelevisionPlus-1.2.0-GoogleTV.apk\",\"browser_download_url\":\"https://x/apk\",\"digest\":\"sha256:abc\"}]}";
        Updater.Info info = Updater.parse(json, "1.1.1");
        assertEquals("1.2.0", info.version);
        assertEquals("https://x/apk", info.apkUrl);
        assertEquals("abc", info.sha256);
        assertNull(Updater.parse(json, "1.2.0"));
    }

    @Test(expected = Exception.class) public void failsWithoutApk() throws Exception {
        Updater.parse("{\"tag_name\":\"v2.0.0\",\"assets\":[]}", "1.1.1");
    }
}
