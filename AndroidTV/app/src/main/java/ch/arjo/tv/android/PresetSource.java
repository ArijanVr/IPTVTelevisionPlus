package ch.arjo.tv.android;

/** Apply a new bundled source once; retain later user choices and explicit sign-out. */
final class PresetSource {
    static Source choose(Source saved,String configuredUrl,String appliedScope) {
        if(configuredUrl==null||configuredUrl.isEmpty())return saved;
        Source preset=new Source("m3u",configuredUrl,"","");
        return preset.scope().equals(appliedScope)?saved:preset;
    }
}
