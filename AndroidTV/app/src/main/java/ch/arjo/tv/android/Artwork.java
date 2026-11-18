package ch.arjo.tv.android;

import android.graphics.*;
import android.graphics.drawable.*;
import android.os.Handler;
import android.os.Looper;
import android.util.LruCache;
import android.widget.ImageView;
import java.io.*;
import java.net.*;
import java.util.concurrent.*;

/** Bounded memory-only artwork cache; provider addresses are never logged or written to disk. */
final class Artwork implements AutoCloseable {
    private final ExecutorService pool=new ThreadPoolExecutor(2,2,0L,TimeUnit.MILLISECONDS,new ArrayBlockingQueue<>(40),new ThreadPoolExecutor.DiscardPolicy());
    private final Handler main=new Handler(Looper.getMainLooper());
    private final LruCache<String,Bitmap> cache=new LruCache<>(20*1024*1024) { @Override protected int sizeOf(String key,Bitmap b) { return b.getAllocationByteCount(); } };
    private volatile boolean closed;
    void load(ImageView view,String url,boolean logo) {
        view.setTag(url); view.setImageDrawable(new Placeholder(logo));
        view.setScaleType(logo ? ImageView.ScaleType.FIT_CENTER : ImageView.ScaleType.CENTER_CROP);
        if (!Source.isWeb(url) || closed) return;
        String key=Source.hash(url); Bitmap hit=cache.get(key);
        if (hit!=null) { view.setImageBitmap(hit); return; }
        pool.execute(()-> {
            Bitmap bitmap=null; HttpURLConnection connection=null;
            try {
                connection=(HttpURLConnection)URI.create(url).toURL().openConnection(); connection.setConnectTimeout(8000); connection.setReadTimeout(8000);
                connection.setRequestProperty("User-Agent","ARJOTV-Android/0.2");
                if (connection.getResponseCode()!=200 || connection.getContentLengthLong()>6*1024*1024) return;
                byte[] bytes;
                try (InputStream in=connection.getInputStream(); ByteArrayOutputStream out=new ByteArrayOutputStream()) {
                    byte[] chunk=new byte[8192]; int n;
                    while ((n=in.read(chunk))!=-1) { if (out.size()+n>6*1024*1024 || closed) return; out.write(chunk,0,n); }
                    bytes=out.toByteArray();
                }
                BitmapFactory.Options options=new BitmapFactory.Options(); options.inJustDecodeBounds=true; BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);
                if (options.outWidth<=0 || options.outHeight<=0) return;
                options.inSampleSize=1; while (Math.max(options.outWidth,options.outHeight)/options.inSampleSize>1024) options.inSampleSize*=2;
                options.inJustDecodeBounds=false; bitmap=BitmapFactory.decodeByteArray(bytes,0,bytes.length,options);
                if (bitmap!=null) cache.put(key,bitmap);
            } catch (Exception ignored) { /* A missing image must never block navigation. */ }
            finally { if (connection!=null) connection.disconnect(); }
            Bitmap result=bitmap;
            if (result!=null && !closed) main.post(()-> { if (!closed && url.equals(view.getTag())) view.setImageBitmap(result); });
        });
    }
    @Override public void close() { closed=true; pool.shutdownNow(); main.removeCallbacksAndMessages(null); cache.evictAll(); }
    static final class Placeholder extends Drawable {
        private final boolean logo;
        Placeholder(boolean logo) { this.logo=logo; }
        @Override public void draw(Canvas c) {
            Rect b=getBounds(); Paint p=new Paint(Paint.ANTI_ALIAS_FLAG);
            p.setShader(new LinearGradient(b.left,b.top,b.right,b.bottom,new int[]{0xFF252828,0xFF121414},null,Shader.TileMode.CLAMP)); c.drawRect(b,p); p.setShader(null);
            float cx=b.exactCenterX(),cy=b.exactCenterY(),w=Math.min(b.width()*.36f,b.height()*.55f),h=w*(logo?.65f:1.2f);
            p.setColor(0xFF747B78); p.setStyle(Paint.Style.STROKE); p.setStrokeWidth(Math.max(2,b.width()/120f));
            c.drawRoundRect(cx-w/2,cy-h/2,cx+w/2,cy+h/2,5,5,p);
            if (logo) { c.drawLine(cx-w*.2f,cy+h*.7f,cx+w*.2f,cy+h*.7f,p); }
            else { c.drawLine(cx-w*.3f,cy-h/2,cx-w*.3f,cy+h/2,p); c.drawLine(cx+w*.3f,cy-h/2,cx+w*.3f,cy+h/2,p); }
        }
        @Override public void setAlpha(int alpha) { }
        @Override public void setColorFilter(ColorFilter filter) { }
        @Override public int getOpacity() { return PixelFormat.OPAQUE; }
    }
}
