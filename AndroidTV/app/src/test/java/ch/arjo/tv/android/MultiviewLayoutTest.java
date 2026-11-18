package ch.arjo.tv.android;

import org.junit.Test;
import static org.junit.Assert.*;

public class MultiviewLayoutTest {
    private static float area(float[][] frames){float a=0;for(float[] f:frames)a+=f[2]*f[3];return a;}
    @Test public void everyLayoutExceptPipFillsTheScreenWithoutEmptyFieldsOrOverlap(){
        for(String key:MultiviewLayout.KEYS){if(MultiviewLayout.overlaps(key))continue;
            for(int count=1;count<=4;count++){float[][] f=MultiviewLayout.frames(key,count,1200,600,count-1);
                assertEquals(key+" "+count,count,f.length);assertEquals(key+" "+count,1200*600,area(f),.5f);
                for(int i=0;i<f.length;i++)for(int j=i+1;j<f.length;j++){float w=Math.min(f[i][0]+f[i][2],f[j][0]+f[j][2])-Math.max(f[i][0],f[j][0]),h=Math.min(f[i][1]+f[i][3],f[j][1]+f[j][3])-Math.max(f[i][1],f[j][1]);assertTrue(key+" overlap",w<=.5f||h<=.5f);}
            }}
    }
    @Test public void gridWithThreeSpansTheLastPictureOverTheFullWidth(){
        float[][] f=MultiviewLayout.frames("grid",3,1200,600,0);
        assertArrayEquals(new float[]{0,0,600,300},f[0],.01f);assertArrayEquals(new float[]{600,0,600,300},f[1],.01f);assertArrayEquals(new float[]{0,300,1200,300},f[2],.01f);
    }
    @Test public void pictureInPictureKeepsTheMainFullAndFloatsTheOthersInTheCorner(){
        float[][] f=MultiviewLayout.frames("pip",3,1600,900,1);
        assertArrayEquals(new float[]{0,0,1600,900},f[1],.01f);
        for(int i:new int[]{0,2}){assertTrue(f[i][0]>800);assertTrue(f[i][0]+f[i][2]<=1600);assertTrue(f[i][1]>=0&&f[i][1]+f[i][3]<=900);assertEquals(16f/9f,f[i][2]/f[i][3],.01f);}
        assertTrue("kleine Bilder überlappen sich nicht",f[0][1]>=f[2][1]+f[2][3]||f[2][1]>=f[0][1]+f[0][3]);
        assertEquals("Raster",MultiviewLayout.label("unbekannt"));
    }
}
