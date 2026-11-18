package ch.arjo.tv.android;

import android.app.Activity;
import android.graphics.*;
import android.graphics.drawable.BitmapDrawable;
import android.widget.ImageView;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.annotation.*;
import org.robolectric.android.controller.ActivityController;
import okhttp3.mockwebserver.*;
import okio.Buffer;
import java.io.ByteArrayOutputStream;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=28)
@GraphicsMode(GraphicsMode.Mode.NATIVE)
public class ArtworkTest {
    @Test public void downloadsArtworkAndKeepsItOnlyInBoundedMemoryCache()throws Exception{
        try(MockWebServer server=new MockWebServer();ActivityController<Activity> controller=Robolectric.buildActivity(Activity.class).setup();Artwork artwork=new Artwork()){
            Bitmap original=Bitmap.createBitmap(40,60,Bitmap.Config.ARGB_8888);original.eraseColor(0xFF335577);ByteArrayOutputStream bytes=new ByteArrayOutputStream();original.compress(Bitmap.CompressFormat.PNG,100,bytes);
            server.enqueue(new MockResponse().setHeader("Content-Type","image/png").setBody(new Buffer().write(bytes.toByteArray())));server.start();
            ImageView first=new ImageView(controller.get());String url=server.url("/poster.png").toString();artwork.load(first,url,false);
            for(int i=0;i<200&&!(first.getDrawable() instanceof BitmapDrawable);i++){Thread.sleep(10);Shadows.shadowOf(android.os.Looper.getMainLooper()).idle();}
            assertTrue(first.getDrawable() instanceof BitmapDrawable);assertEquals(40,((BitmapDrawable)first.getDrawable()).getBitmap().getWidth());
            ImageView second=new ImageView(controller.get());artwork.load(second,url,false);assertTrue(second.getDrawable() instanceof BitmapDrawable);assertEquals(1,server.getRequestCount());
        }
    }
}
