package ch.arjo.tv.android;

import java.util.*;

/** Keep live URLs in process memory, never in a large Intent or a plaintext playlist file. */
final class PlaybackQueue {
    private static String activeToken;
    private static PlaybackQueue active;
    private final List<Entry> all=new ArrayList<>();
    private final List<String> groupOrder;
    private final List<Entry> channels=new ArrayList<>();
    final String scope;
    private int index;
    private String previousId;
    PlaybackQueue(List<Entry> catalog,Entry selected,String scope){this(catalog,selected,scope,Collections.emptyList());}
    PlaybackQueue(List<Entry> catalog,Entry selected,String scope,List<String> groupOrder){
        this.scope=scope;this.groupOrder=new ArrayList<>(groupOrder);Set<String> ids=new HashSet<>();
        for(Entry entry:catalog)if(entry.kind.equals("live")&&Source.isWeb(entry.url)&&ids.add(entry.id))all.add(entry);
        loadGroup(selected.group,selected);
    }
    private void loadGroup(String group,Entry selected){
        channels.clear();
        for(Entry entry:all)if(entry.group.equals(group))channels.add(entry);
        // Nach Kanalnummer; ohne Nummern bleibt die Reihenfolge des Anbieters (stabile Sortierung).
        channels.sort(Comparator.comparingInt(e->e.number<=0?Integer.MAX_VALUE:e.number));
        index=-1;for(int i=0;i<channels.size();i++)if(channels.get(i).id.equals(selected.id)){index=i;break;}
        if(index<0){channels.add(selected);index=channels.size()-1;}
    }
    Entry current(){return channels.get(index);}
    Entry move(int direction){previousId=current().id;index=Math.floorMod(index+(direction>0?1:-1),channels.size());return current();}
    void select(String id){for(int i=0;i<channels.size();i++)if(channels.get(i).id.equals(id)){index=i;return;}}
    int size(){return channels.size();}
    /** Gruppen in eigener Reihenfolge (Meine Listen); nicht genannte folgen in der Reihenfolge des Anbieters. */
    List<String> groups(){
        Set<String> present=new LinkedHashSet<>();for(Entry e:all)present.add(e.group);
        List<String> out=new ArrayList<>();for(String g:groupOrder)if(present.remove(g))out.add(g);out.addAll(present);return out;
    }
    ChannelNavigator.GroupPosition neighbourGroup(String from,int direction){
        ChannelNavigator nav=new ChannelNavigator(groups());nav.setCurrentGroup(from);return nav.neighbourGroup(direction);
    }
    /** Startet die Gruppe mit ihrem ersten Kanal (kleinste Nummer); null, wenn sie leer ist. */
    Entry startGroup(String group){
        Entry first=null;for(Entry e:all)if(e.group.equals(group)&&(first==null||rank(e)<rank(first)))first=e;
        if(first==null)return null;previousId=current().id;loadGroup(group,first);return current();
    }
    private static int rank(Entry e){return e.number<=0?Integer.MAX_VALUE:e.number;}
    Entry byNumber(int number){for(Entry e:all)if(e.number==number)return e;return null;}
    /** Springt zu einem Sender; liegt er in der laufenden Gruppe, bleibt sie, sonst gilt seine Gruppe. */
    Entry jump(Entry target){
        previousId=current().id;
        for(int i=0;i<channels.size();i++)if(channels.get(i).id.equals(target.id)){index=i;return current();}
        loadGroup(target.group,target);return current();
    }
    /** Der vorher gesehene Sender («Letzter Kanal»); null ohne Verlauf. */
    Entry previous(){
        if(previousId==null)return null;
        for(Entry e:all)if(e.id.equals(previousId))return jump(e);
        return null;
    }
    Entry first(){Entry first=null;for(Entry e:all)if(first==null||rank(e)<rank(first))first=e;return first;}
    static synchronized String register(PlaybackQueue queue){active=queue;activeToken=UUID.randomUUID().toString();return activeToken;}
    static synchronized PlaybackQueue get(String token){return token!=null&&token.equals(activeToken)?active:null;}
    static synchronized void clear(String token){if(token!=null&&token.equals(activeToken)){active=null;activeToken=null;}}
}
