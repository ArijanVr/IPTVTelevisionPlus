package ch.arjo.tv.android;

import java.util.*;

/** Feste Kanalnummern nach docs/TV-MODUS-SPEZIFIKATION.md: Nutzer, bisherige Nummer, Nummer der Quelle, dann fortlaufend. */
final class ChannelNumbers {
    static final class Result {
        final Map<String,Integer> numbers;final int duplicates;
        Result(Map<String,Integer> numbers,int duplicates){this.numbers=numbers;this.duplicates=duplicates;}
    }
    private ChannelNumbers(){}
    /** @param sourceNumbers Nummer der Quelle je Kanal in gleicher Reihenfolge wie ids; 0 oder weniger = keine. */
    static Result assign(List<String> ids,List<Integer> sourceNumbers,Map<String,Integer> existing,Map<String,Integer> pinned){
        Map<String,Integer> numbers=new HashMap<>();Set<Integer> used=new HashSet<>();
        for(String id:ids){Integer n=pinned.get(id);if(n!=null)take(numbers,used,id,n);}
        for(String id:ids){Integer n=existing.get(id);if(n!=null)take(numbers,used,id,n);}
        int duplicates=0;List<String> rest=new ArrayList<>();
        for(int i=0;i<ids.size();i++){
            String id=ids.get(i);if(numbers.containsKey(id))continue;
            int source=sourceNumbers==null||i>=sourceNumbers.size()||sourceNumbers.get(i)==null?0:sourceNumbers.get(i);
            if(source>=1){if(!take(numbers,used,id,source)){duplicates++;rest.add(id);}}else rest.add(id);
        }
        int next=existing.isEmpty()&&pinned.isEmpty()?1:(used.isEmpty()?0:Collections.max(used))+1;
        for(String id:rest){
            if(numbers.containsKey(id))continue;
            while(used.contains(next))next++;
            numbers.put(id,next);used.add(next);next++;
        }
        return new Result(numbers,duplicates);
    }
    private static boolean take(Map<String,Integer> numbers,Set<Integer> used,String id,int number){
        if(number<1||numbers.containsKey(id)||used.contains(number))return false;
        numbers.put(id,number);used.add(number);return true;
    }
}
