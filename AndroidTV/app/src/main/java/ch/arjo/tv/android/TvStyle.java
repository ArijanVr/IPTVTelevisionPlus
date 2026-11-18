package ch.arjo.tv.android;

import android.app.Activity;
import android.content.res.ColorStateList;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.graphics.drawable.StateListDrawable;
import android.view.*;
import android.widget.*;

final class TvStyle {
    // Tokens «IP Television+» (dunkler Modus, am Fernseher immer): Off-White auf Black, Graphite für Flächen.
    // Genau ein Akzent, Glut: nur Fortschritt, Live-Punkt, Status-Punkt, Fehler-Icon, «+» der Wortmarke und Fokusring.
    // Nie als Textfarbe und nie als grosse Fläche. Radien: Chip 6, Control 8, Karte 12, Sheet 20.
    static final int BLACK=0xFF090A0A, RAISED=0xFF1A1B1D, WHITE=0xFFFDFDFC, GRAPHITE=0xFF2A2C2C, ELEVATED=0xFF2A2C2C, SECONDARY=0xFFD9DAD8, TEXT2=SECONDARY, DIVIDER=0xFF2A2C2C, BORDER=0xFF6B6E6D, GLUT=0xFFFC5F39;
    static final int SIGNAL=GLUT;
    static final int R_CHIP=6, R_CONTROL=8, R_CARD=12, R_SHEET=20;
    private static final android.view.animation.Interpolator STANDARD=new android.view.animation.PathInterpolator(0.2f,0f,0f,1f);
    /** Guide-Pixel bei 1080p, auf die tatsächliche Bildschirmhöhe umgerechnet. */
    static float px(Activity a,float guidePx) { return guidePx*a.getResources().getDisplayMetrics().heightPixels/1080f; }
    static Typeface font(Activity a,int res) { try { return a.getResources().getFont(res); } catch (Exception e) { return Typeface.SANS_SERIF; } }
    /** Stufen aus dem Guide: Micro/Small 24, Body 28, Headline 32, Title2 40, Title1 52, Display 72 (alte Grössen werden eingeordnet). */
    static float guide(int legacy) { return legacy<=16?24:legacy<=20?28:legacy<=24?32:legacy<=30?40:legacy<=36?52:72; }
    static int dp(Activity a,int n) { return Math.round(n*a.getResources().getDisplayMetrics().density); }
    static TextView text(Activity a,String value,int size) {
        TextView v=new TextView(a); v.setText(value); v.setTextColor(WHITE); v.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX,px(a,Math.min(guide(size),size<=16?24:28))); v.setTypeface(font(a,R.font.geist_regular)); v.setFontFeatureSettings("kern"); v.setIncludeFontPadding(false); return v;
    }
    static TextView title(Activity a,String value,int size) { TextView v=text(a,value,size); v.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX,px(a,guide(size))); v.setTypeface(font(a,R.font.geist_medium)); return v; }
    static GradientDrawable shape(int fill,int stroke) { return shape(fill,stroke,14); }
    static GradientDrawable shape(int fill,int stroke,int radius) { GradientDrawable d=new GradientDrawable(); d.setColor(fill); d.setCornerRadius(radius); if (stroke!=Color.TRANSPARENT) d.setStroke(2,stroke); return d; }
    static void focusable(View view) { focusable(view,false); }
    static void focusable(View view,boolean primary) {
        // Primär und ausgewählt: Off-White-Fläche mit schwarzem Text, sonst Graphite mit Off-White-Text; Pille.
        // Fokus: Off-White-Pille mit schwarzem Text und dünnem Glut-Ring (so bleibt Fokus von «ausgewählt» unterscheidbar), dazu Skalierung 1.04. Deaktiviert: 50 %.
        int fill=primary ? WHITE : GRAPHITE;
        float ringPx=ringPx(view.getContext());
        StateListDrawable bg=new StateListDrawable();
        bg.addState(new int[]{android.R.attr.state_focused},shapePx(WHITE,GLUT,1000,ringPx));
        bg.addState(new int[]{android.R.attr.state_pressed},shape(SECONDARY,Color.TRANSPARENT,1000));
        bg.addState(new int[]{android.R.attr.state_selected},shape(WHITE,Color.TRANSPARENT,1000));
        bg.addState(new int[]{-android.R.attr.state_enabled},shape(fill&0x80FFFFFF,Color.TRANSPARENT,1000));
        bg.addState(new int[]{},shape(fill,Color.TRANSPARENT,1000));
        view.setBackground(bg); view.setFocusable(true); view.setId(View.generateViewId());
        scaleOnFocus(view,null);
        if (view instanceof TextView) ((TextView)view).setTextColor(new ColorStateList(
            new int[][]{{android.R.attr.state_focused},{android.R.attr.state_pressed},{android.R.attr.state_selected},{}},new int[]{BLACK,BLACK,BLACK,primary ? BLACK : WHITE}));
    }
    static GradientDrawable shape(int fill,int stroke,int radius,int strokePx) { GradientDrawable d=new GradientDrawable(); d.setColor(fill); d.setCornerRadius(radius*3); d.setStroke(strokePx*3,stroke); return d; }
    static GradientDrawable shapePx(int fill,int stroke,float radiusPx,float strokePx) { GradientDrawable d=new GradientDrawable(); d.setColor(fill); d.setCornerRadius(radiusPx); d.setStroke(Math.max(1,Math.round(strokePx)),stroke); return d; }
    /** Dicke des Fokusrings: 3 px bei 1080p. */
    static float ringPx(android.content.Context c) { return Math.max(2f,3f*c.getResources().getDisplayMetrics().heightPixels/1080f); }
    static float radiusPx(android.content.Context c,float guide) { return guide*c.getResources().getDisplayMetrics().heightPixels/1080f; }
    /** Fokus (10-Fuss): dünner Glut-Ring (3 px bei 1080p) und Skalierung. */
    static GradientDrawable focusShape(android.content.Context c,int fill,int radiusGuide) { return shapePx(fill,GLUT,radiusPx(c,radiusGuide),ringPx(c)); }
    /** Karten wachsen beim Fokus deutlicher als Knöpfe (Google TV). */
    static final float CARD_SCALE=1.08f, BUTTON_SCALE=1.04f;
    /** Fokusebene über Bildern: unsichtbar, der Fokus kommt von `glow` (Schatten) und der Skalierung. */
    static GradientDrawable focusRing(android.content.Context c,int radiusGuide) { return focusShape(c,Color.TRANSPARENT,radiusGuide); }
    /** Hebt eine Fläche an (neutraler Schatten). Die Fläche braucht einen deckenden Hintergrund (Umriss für den Schatten). */
    static void glow(View v,boolean on) { v.setElevation(dp((Activity)v.getContext(),on?12:0)); }
    /** Fokus: Skalierung 1.04 in 240 ms (Kurve 0.2 / 0 / 0 / 1, Guide S. 8 und 10); ohne Systemanimationen (Bewegung reduzieren) nur der Ring. */
    static void scaleOnFocus(View view,Runnable onFocus) { scaleOnFocus(view,onFocus,null); }
    static void scaleOnFocus(View view,Runnable onFocus,java.util.function.Consumer<Boolean> changed) { scaleOnFocus(view,onFocus,changed,BUTTON_SCALE); }
    static void scaleOnFocus(View view,Runnable onFocus,java.util.function.Consumer<Boolean> changed,float scale) {
        view.setOnFocusChangeListener((v,hasFocus)-> {
            if (changed!=null) changed.accept(hasFocus);
            boolean animate=android.animation.ValueAnimator.areAnimatorsEnabled();
            v.animate().cancel();
            if (animate) v.animate().scaleX(hasFocus?scale:1f).scaleY(hasFocus?scale:1f).setDuration(hasFocus?240:180).setInterpolator(STANDARD).start();
            else { v.setScaleX(1); v.setScaleY(1); }
            glow(v,hasFocus);
            if (hasFocus && onFocus!=null) onFocus.run();
        });
    }
    static void cardFocus(View view,Runnable onFocus) { cardFocus(view,onFocus,RAISED); }
    /** Karte mit Fokusring: Fläche `fill`, im Fokus Graphite mit Glut-Ring. */
    static void cardFocus(View view,Runnable onFocus,int fill) {
        StateListDrawable bg=new StateListDrawable();
        android.content.Context c=view.getContext();
        bg.addState(new int[]{android.R.attr.state_focused},focusShape(c,GRAPHITE,R_CARD));
        bg.addState(new int[]{},shapePx(fill,Color.TRANSPARENT,radiusPx(c,R_CARD),0));
        view.setBackground(bg); view.setFocusable(true); view.setClickable(true); view.setId(View.generateViewId());
        scaleOnFocus(view,onFocus);
    }
    /** Eingabefeld: Graphite mit Control-Rand (#6B6E6D), im Fokus Glut-Ring. */
    static StateListDrawable inputBackground(android.content.Context c) {
        StateListDrawable bg=new StateListDrawable();
        bg.addState(new int[]{android.R.attr.state_focused},focusShape(c,GRAPHITE,R_CONTROL));
        bg.addState(new int[]{},shapePx(GRAPHITE,BORDER,radiusPx(c,R_CONTROL),1));
        return bg;
    }
    /** Wortmarke «IP Television+»: Geist Medium, das «+» in Glut (einzige Textstelle mit Akzent). */
    static TextView wordmark(Activity a,float guideSize) {
        TextView v=new TextView(a); android.text.SpannableString t=new android.text.SpannableString("IP Television+");
        t.setSpan(new android.text.style.ForegroundColorSpan(GLUT),t.length()-1,t.length(),0);
        v.setText(t); v.setTextColor(WHITE); v.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX,px(a,guideSize)); v.setTypeface(font(a,R.font.geist_medium)); v.setIncludeFontPadding(false); v.setSingleLine(true);
        v.setContentDescription("IP Television+"); return v;
    }
    /** Signet 16 px bei 1080p: schwarzes Quadrat (Radius 4) mit kleinem Glut-Punkt unten rechts. */
    static View signet(Activity a) {
        final float size=px(a,16),radius=px(a,4),dot=px(a,2.5f),line=Math.max(1f,px(a,1));
        View v=new View(a) {
            final android.graphics.Paint paint=new android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG);
            @Override protected void onDraw(android.graphics.Canvas c) {
                android.graphics.RectF r=new android.graphics.RectF(line/2,line/2,getWidth()-line/2,getHeight()-line/2);
                paint.setStyle(android.graphics.Paint.Style.FILL); paint.setColor(BLACK); c.drawRoundRect(r,radius,radius,paint);
                paint.setStyle(android.graphics.Paint.Style.STROKE); paint.setStrokeWidth(line); paint.setColor(BORDER); c.drawRoundRect(r,radius,radius,paint);
                paint.setStyle(android.graphics.Paint.Style.FILL); paint.setColor(GLUT); c.drawCircle(getWidth()-dot*2f,getHeight()-dot*2f,dot,paint);
            }
        };
        v.setLayoutParams(new LinearLayout.LayoutParams(Math.round(size),Math.round(size))); v.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO); return v;
    }
    /** «Ein Produkt von ARJO LAB»: Geist Mono 12 px, Versalien, gesperrt, davor das Signet. */
    static LinearLayout arjoLine(Activity a) {
        LinearLayout row=row(a); row.setGravity(Gravity.CENTER_VERTICAL); row.setContentDescription("Ein Produkt von ARJO LAB");
        View mark=signet(a); LinearLayout.LayoutParams mp=new LinearLayout.LayoutParams(Math.round(px(a,16)),Math.round(px(a,16))); mp.rightMargin=Math.round(px(a,10)); row.addView(mark,mp);
        TextView t=new TextView(a); t.setText("EIN PRODUKT VON ARJO LAB"); t.setTextColor(SECONDARY); t.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX,px(a,12)); t.setLetterSpacing(.16f); t.setTypeface(font(a,R.font.geist_mono_regular)); t.setIncludeFontPadding(false); t.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        row.addView(t); return row;
    }
    static Button button(Activity a,String label,Runnable action) { return button(a,label,false,action); }
    static Button button(Activity a,String label,boolean primary,Runnable action) {
        Button b=new Button(a); b.setText(label); b.setTextSize(android.util.TypedValue.COMPLEX_UNIT_PX,px(a,24)); b.setAllCaps(false); b.setTypeface(font(a,R.font.geist_medium));
        b.setMinHeight(0); b.setMinimumHeight(Math.round(px(a,64))); b.setMinWidth(0); b.setMinimumWidth(0); b.setPadding(dp(a,18),0,dp(a,18),0);
        b.setStateListAnimator(null); focusable(b,primary); b.setOnClickListener(v->action.run()); return b;
    }
    static LinearLayout column(Activity a) { LinearLayout l=new LinearLayout(a); l.setOrientation(LinearLayout.VERTICAL); return l; }
    static LinearLayout row(Activity a) { LinearLayout l=new LinearLayout(a); l.setOrientation(LinearLayout.HORIZONTAL); return l; }
    static void pad(Activity a,View v,int h,int vertical) { v.setPadding(dp(a,h),dp(a,vertical),dp(a,h),dp(a,vertical)); }
    static void fullscreen(Activity a) { a.getWindow().getDecorView().setSystemUiVisibility(View.SYSTEM_UI_FLAG_FULLSCREEN|View.SYSTEM_UI_FLAG_HIDE_NAVIGATION|View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY); }
}
