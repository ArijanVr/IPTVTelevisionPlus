package ch.arjo.tv.android;

import org.junit.Test;
import static org.junit.Assert.*;

public class PresetSourceTest {
    private final String address="https://example.test/playlist.m3u?dl=1";
    @Test public void freshInstallUsesM3uWithoutLogin(){Source chosen=PresetSource.choose(null,address,"");assertEquals("m3u",chosen.mode);assertEquals(address,chosen.address);}
    @Test public void updateAppliesNewPresetOnce(){Source old=new Source("m3u","https://example.test/old.m3u","","");assertEquals(address,PresetSource.choose(old,address,old.scope()).address);}
    @Test public void laterUserSelectionIsPreserved(){Source custom=new Source("m3u","https://example.test/custom.m3u","","");String applied=new Source("m3u",address,"","").scope();assertSame(custom,PresetSource.choose(custom,address,applied));}
    @Test public void explicitSignOutDoesNotReAddPreset(){assertNull(PresetSource.choose(null,address,new Source("m3u",address,"","").scope()));}
    @Test public void genericBuildRetainsLogin(){assertNull(PresetSource.choose(null,"",""));}
}
