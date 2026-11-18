package ch.arjo.tv.android;

/** Anordnung der Bilder im Multiview (wie in der Apple-Version). Nur so viele Felder wie laufende Sender: ausser bei «Bild in Bild» füllen sie die Fläche ganz. */
final class MultiviewLayout {
    static final String[] KEYS={"grid","focus","stage","strip","pip"}, LABELS={"Raster","Fokus","Bühne","Reihe","Bild in Bild"};
    private MultiviewLayout(){}
    static String label(String key){for(int i=0;i<KEYS.length;i++)if(KEYS[i].equals(key))return LABELS[i];return LABELS[0];}
    static boolean overlaps(String key){return "pip".equals(key);}
    /** Rechtecke {x, y, Breite, Höhe} für `count` Bilder; `focus` ist das grosse Bild (Fokus, Bühne, Bild in Bild). */
    static float[][] frames(String key,int count,float w,float h,int focus){
        float[][] out=new float[Math.max(count,0)][];if(count<=0)return out;
        boolean landscape=w>=h;int big=Math.min(Math.max(focus,0),count-1);
        if(count==1&&!"strip".equals(key)&&!"grid".equals(key)){out[0]=new float[]{0,0,w,h};return out;}
        switch(key){
            case "focus":{
                float bw=landscape?w*.7f:w,bh=landscape?h:h*.62f;int small=count-1,s=0;
                for(int i=0;i<count;i++){if(i==big){out[i]=new float[]{0,0,bw,bh};continue;}
                    out[i]=landscape?new float[]{bw,h/small*s,w-bw,h/small}:new float[]{w/small*s,bh,w/small,h-bh};s++;}
                return out;
            }
            case "stage":{
                float bh=h*(landscape?.74f:.55f);int small=count-1,s=0;
                for(int i=0;i<count;i++){if(i==big){out[i]=new float[]{0,0,w,bh};continue;}out[i]=new float[]{w/small*s,bh,w/small,h-bh};s++;}
                return out;
            }
            case "strip":
                for(int i=0;i<count;i++)out[i]=landscape?new float[]{w/count*i,0,w/count,h}:new float[]{0,h/count*i,w,h/count};
                return out;
            case "pip":{
                float margin=Math.min(w,h)*.04f,sw=w*(landscape?.22f:.4f),sh=sw*9/16;int s=0;
                for(int i=0;i<count;i++){if(i==big){out[i]=new float[]{0,0,w,h};continue;}out[i]=new float[]{w-margin-sw,h-margin-sh-(sh+margin/2)*s,sw,sh};s++;}
                return out;
            }
            default:{
                // Raster: 3 Bilder = 2 oben, 1 unten über die ganze Breite.
                int[] rows=count==1?new int[]{1}:count==2?(landscape?new int[]{2}:new int[]{1,1}):count==3?new int[]{2,1}:new int[]{2,2};
                float rh=h/rows.length;int n=0;
                for(int r=0;r<rows.length;r++)for(int c=0;c<rows[r]&&n<count;c++)out[n++]=new float[]{w/rows[r]*c,rh*r,w/rows[r],rh};
                return out;
            }
        }
    }
}
