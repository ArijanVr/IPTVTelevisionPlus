package ch.arjo.tv.android;

import java.util.*;
import org.junit.Test;
import static org.junit.Assert.*;

public class ChannelNumbersTest {
    private static List<String> ids(String... s){return Arrays.asList(s);}
    private static List<Integer> src(Integer... n){return Arrays.asList(n);}
    private static Map<String,Integer> map(Object... kv){Map<String,Integer> m=new HashMap<>();for(int i=0;i<kv.length;i+=2)m.put((String)kv[i],(Integer)kv[i+1]);return m;}
    private static final Map<String,Integer> NONE=Collections.emptyMap();

    @Test public void n1SequentialFromOne(){assertEquals(map("a",1,"b",2,"c",3),ChannelNumbers.assign(ids("a","b","c"),src(0,0,0),NONE,NONE).numbers);}
    @Test public void n2SourceNumbersWin(){assertEquals(map("b",1,"c",5,"a",2,"d",3),ChannelNumbers.assign(ids("a","b","c","d"),src(0,1,5,0),NONE,NONE).numbers);}
    @Test public void n3DuplicateSourceFirstKeeps(){
        ChannelNumbers.Result r=ChannelNumbers.assign(ids("a","b","c"),src(7,7,0),NONE,NONE);
        assertEquals(map("a",7,"b",1,"c",2),r.numbers);assertEquals(1,r.duplicates);
    }
    @Test public void n4UpdateKeepsExisting(){
        Map<String,Integer> n=ChannelNumbers.assign(ids("n","c","a"),src(0,0,0),map("a",1,"b",2,"c",3),NONE).numbers;
        assertEquals(map("a",1,"c",3,"n",4),n);
    }
    @Test public void n5ExistingBeatsOtherSource(){
        Map<String,Integer> n=ChannelNumbers.assign(ids("x","a"),src(2,0),map("a",2),NONE).numbers;
        assertEquals(Integer.valueOf(2),n.get("a"));assertNotEquals(Integer.valueOf(2),n.get("x"));
    }
    @Test public void n6PinnedBeatsExisting(){
        Map<String,Integer> n=ChannelNumbers.assign(ids("a","b"),src(0,0),map("a",1,"b",2),map("b",1)).numbers;
        assertEquals(Integer.valueOf(1),n.get("b"));assertNotEquals(Integer.valueOf(1),n.get("a"));assertEquals(2,new HashSet<>(n.values()).size());
    }
    @Test public void n7InvalidIgnoredAndDuplicateIdsOneNumber(){assertEquals(map("a",1,"b",2),ChannelNumbers.assign(ids("a","a","b"),src(0,0,-3),NONE,NONE).numbers);}
    @Test public void manyChannelsAreUnique(){
        List<String> ids=new ArrayList<>();List<Integer> s=new ArrayList<>();for(int i=0;i<5000;i++){ids.add("id"+i);s.add(i%7==0?3:0);}
        Map<String,Integer> n=ChannelNumbers.assign(ids,s,NONE,NONE).numbers;
        assertEquals(5000,n.size());assertEquals(5000,new HashSet<>(n.values()).size());
    }
}
