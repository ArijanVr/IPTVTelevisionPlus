package ch.arjo.tv.android;

import java.util.*;
import org.junit.Test;
import static org.junit.Assert.*;

public class ChannelNavigatorTest {
    private static List<ChannelNavigator.Item> items(int... numbers){List<ChannelNavigator.Item> l=new ArrayList<>();for(int n:numbers)l.add(new ChannelNavigator.Item("k"+n,n));return l;}
    private ChannelNavigator nav(){ChannelNavigator n=new ChannelNavigator(Arrays.asList("Schweiz","Sport","Kino"));n.load("Schweiz",items(3,1,2),null);return n;}

    @Test public void z1LoadSortsAndSelectsFirst(){ChannelNavigator n=nav();assertEquals(1,n.current().number);assertEquals(3,n.items().get(2).number);}
    @Test public void z2ZapWraps(){ChannelNavigator n=nav();assertEquals(3,n.zap(-1).number);assertEquals(1,n.zap(1).number);assertEquals(2,n.zap(1).number);}
    @Test public void zapSingleItemStays(){ChannelNavigator n=new ChannelNavigator(Arrays.asList("A"));n.load("A",items(5),null);assertEquals(5,n.zap(1).number);}
    @Test public void z3GroupStepWraps(){
        ChannelNavigator n=nav();
        assertEquals(new ChannelNavigator.GroupPosition("Sport",2,3),n.neighbourGroup(1));
        assertEquals(new ChannelNavigator.GroupPosition("Kino",3,3),n.neighbourGroup(-1));
        n.load("Kino",items(30),null);assertEquals("Schweiz",n.neighbourGroup(1).name);
    }
    @Test public void z4SkippedGroups(){ChannelNavigator n=nav();n.setGroups(Arrays.asList("Schweiz","Kino"));assertEquals("Kino",n.neighbourGroup(1).name);}
    @Test public void rapidGroupSteps(){
        ChannelNavigator n=nav();n.load(n.neighbourGroup(1).name,items(10,11),null);
        ChannelNavigator.Item first=n.load(n.neighbourGroup(1).name,items(21,20),null);
        assertEquals(20,first.number);assertEquals(new ChannelNavigator.GroupPosition("Kino",3,3),n.groupPosition());
    }
    @Test public void z5DigitWindow(){
        ChannelNavigator n=nav();n.enter(1,1000);n.enter(2,2000);
        assertEquals(4000,n.commitDeadline());assertEquals(12,n.commitDigits());assertFalse(n.hasPendingDigits());assertEquals(0,n.commitDigits());
    }
    @Test public void z6DigitLimits(){ChannelNavigator n=nav();n.enter(0,0);assertFalse(n.hasPendingDigits());for(int d=1;d<=5;d++)n.enter(d,0);assertEquals(1234,n.commitDigits());}
    @Test public void z7Cancel(){ChannelNavigator n=nav();n.enter(7,0);n.cancelDigits();assertEquals(0,n.commitDigits());assertEquals(Long.MIN_VALUE,n.commitDeadline());}
    @Test public void z8Recall(){ChannelNavigator n=nav();n.zap(1);n.zap(1);assertEquals(2,n.recallPrevious().number);assertEquals(3,n.recallPrevious().number);}
    @Test public void z9RecallWithoutHistory(){assertNull(nav().recallPrevious());}
}
