package ch.arjo.tv.android;

import java.util.*;

/** Zustandsmaschine fürs Zappen nach docs/TV-MODUS-SPEZIFIKATION.md; ohne Wiedergabe und Speicher. */
final class ChannelNavigator {
    static final long DIGIT_WINDOW_MS=2000;
    static final int MAX_DIGITS=4;
    static final class Item{
        final String id;final int number;
        Item(String id,int number){this.id=id;this.number=number;}
    }
    static final class GroupPosition{
        final String name;final int position,count;
        GroupPosition(String name,int position,int count){this.name=name;this.position=position;this.count=count;}
        @Override public boolean equals(Object o){return o instanceof GroupPosition&&((GroupPosition)o).name.equals(name)&&((GroupPosition)o).position==position&&((GroupPosition)o).count==count;}
        @Override public int hashCode(){return Objects.hash(name,position,count);}
    }
    private List<String> groups;
    private String currentGroup,currentId,previousId;
    private List<Item> items=new ArrayList<>();
    private final StringBuilder digits=new StringBuilder();
    private long lastDigitAt=Long.MIN_VALUE;
    ChannelNavigator(List<String> groups){this.groups=new ArrayList<>(groups);}
    void setGroups(List<String> names){groups=new ArrayList<>(names);}
    void setCurrentGroup(String name){currentGroup=name;}
    String currentGroup(){return currentGroup;}
    List<Item> items(){return items;}
    Item current(){for(Item i:items)if(i.id.equals(currentId))return i;return null;}
    Item load(String group,List<Item> list,String selecting){
        currentGroup=group;items=new ArrayList<>(list);items.sort(Comparator.comparingInt(i->i.number));
        Item target=null;for(Item i:items)if(i.id.equals(selecting)){target=i;break;}
        if(target==null&&!items.isEmpty())target=items.get(0);
        return select(target);
    }
    Item zap(int offset){
        if(items.isEmpty())return null;
        int index=-1;for(int i=0;i<items.size();i++)if(items.get(i).id.equals(currentId))index=i;
        if(index<0)return select(items.get(0));
        if(items.size()==1)return current();
        return select(items.get(Math.floorMod(index+offset,items.size())));
    }
    GroupPosition neighbourGroup(int offset){
        if(groups.isEmpty())return null;
        int index=currentGroup==null?-1:groups.indexOf(currentGroup);
        if(index<0)index=offset>=0?-1:0;
        int next=Math.floorMod(index+offset,groups.size());
        return new GroupPosition(groups.get(next),next+1,groups.size());
    }
    GroupPosition groupPosition(){int i=currentGroup==null?-1:groups.indexOf(currentGroup);return i<0?null:new GroupPosition(currentGroup,i+1,groups.size());}
    Item select(String id){for(Item i:items)if(i.id.equals(id))return select(i);return null;}
    Item recallPrevious(){return previousId==null?null:select(previousId);}
    private Item select(Item item){
        if(item==null)return null;
        if(!item.id.equals(currentId)){previousId=currentId;currentId=item.id;}
        return item;
    }
    boolean hasPendingDigits(){return digits.length()>0;}
    String digits(){return digits.toString();}
    void enter(int digit,long nowMs){
        if(digit<0||digit>9)return;
        if(digits.length()==0&&digit==0)return;
        if(digits.length()<MAX_DIGITS)digits.append(digit);
        lastDigitAt=nowMs;
    }
    /** Zeitpunkt, an dem die Eingabe gilt; Long.MIN_VALUE ohne Eingabe. */
    long commitDeadline(){return lastDigitAt==Long.MIN_VALUE?Long.MIN_VALUE:lastDigitAt+DIGIT_WINDOW_MS;}
    /** Beendet die Eingabe; 0, wenn nichts eingegeben war. */
    int commitDigits(){int n=digits.length()==0?0:Integer.parseInt(digits.toString());cancelDigits();return n;}
    void cancelDigits(){digits.setLength(0);lastDigitAt=Long.MIN_VALUE;}
}
