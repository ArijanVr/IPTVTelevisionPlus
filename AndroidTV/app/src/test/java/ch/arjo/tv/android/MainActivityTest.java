package ch.arjo.tv.android;

import android.view.*;
import android.widget.*;
import org.junit.*;
import org.junit.runner.RunWith;
import org.robolectric.*;
import org.robolectric.android.controller.ActivityController;
import org.robolectric.annotation.Config;
import static org.junit.Assert.*;

@RunWith(RobolectricTestRunner.class)
@Config(sdk=28,qualifiers="w960dp-h540dp-land-mdpi")
@org.robolectric.annotation.GraphicsMode(org.robolectric.annotation.GraphicsMode.Mode.NATIVE)
public class MainActivityTest {
    private Button button(View view,String label) {
        if (view instanceof Button && ((Button)view).getText().toString().equals(label)) return (Button)view;
        if (view instanceof ViewGroup) for (int i=0; i<((ViewGroup)view).getChildCount(); i++) {
            Button result=button(((ViewGroup)view).getChildAt(i),label); if (result!=null) return result;
        }
        return null;
    }
    @Test public void onboardingOffersBothSourceTypesAndRemoteFocusableControls() throws Exception {
        try (ActivityController<MainActivity> controller=Robolectric.buildActivity(MainActivity.class).setup()) {
            MainActivity activity=controller.get(); View root=activity.getWindow().getDecorView();
            for (int i=0;i<100 && button(root,"M3U-Playlist")==null;i++) { Thread.sleep(10); Shadows.shadowOf(android.os.Looper.getMainLooper()).idle(); }
            Button m3u=button(root,"M3U-Playlist"); assertNotNull(m3u); assertTrue(m3u.isFocusable());
            assertNotNull(button(root,"Xtream")); assertTrue(button(root,"Anmelden").isFocusable());
            View content=activity.findViewById(android.R.id.content);content.measure(View.MeasureSpec.makeMeasureSpec(960,View.MeasureSpec.EXACTLY),View.MeasureSpec.makeMeasureSpec(540,View.MeasureSpec.EXACTLY));content.layout(0,0,960,540);
            android.graphics.Bitmap bitmap=android.graphics.Bitmap.createBitmap(960,540,android.graphics.Bitmap.Config.ARGB_8888);content.draw(new android.graphics.Canvas(bitmap));java.io.File folder=new java.io.File("build/previews");folder.mkdirs();try(java.io.FileOutputStream out=new java.io.FileOutputStream(new java.io.File(folder,"Anmeldung.png"))){bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG,100,out);}
            m3u.performClick(); assertTrue(button(root,"M3U-Playlist").isSelected());
            button(root,"Anmelden").performClick(); assertTrue(button(root,"Anmelden").isEnabled());
        }
    }
}
