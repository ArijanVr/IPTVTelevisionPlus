(function () {
  var r = window.ARJO_RELEASE;
  var versionEl = document.getElementById("version");
  if (!r) { versionEl.textContent = "Release-Daten fehlen (release-data.js)"; return; }
  versionEl.textContent = "Version " + r.version + " (Build " + r.build + ")";

  function mb(bytes) { return (bytes / 1048576).toFixed(1) + " MB"; }
  function show(key, file, label, sub, missing) {
    var el = document.querySelector('[data-key="' + key + '"]');
    var info = r.files[file];
    if (info) {
      var a = document.createElement("a");
      a.className = "btn"; a.href = "../" + file; a.setAttribute("download", "");
      a.innerHTML = label + "<small>" + sub + " · " + mb(info.size) + "</small>";
      el.appendChild(a);
    } else {
      var d = document.createElement("div");
      d.className = "status"; d.textContent = missing;
      el.appendChild(d);
    }
  }

  show("macOS", "downloads/ARJOTV-macOS.zip", "ARJO TV für Mac laden", "ZIP, universal", "Mac-Build nicht verfügbar.");
  var exp = r.iosExpires ? " · gültig bis " + r.iosExpires.slice(0, 10) : "";
  show("iOS", "downloads/ARJOTV-iOS.ipa", "iPhone-IPA laden", "nur für registrierte Testgeräte" + exp,
       "Geräteinstallation erfordert Apple Signierung.");
  show("tvOS", "downloads/ARJOTV-tvOS.ipa", "Apple-TV-IPA laden", "IPA", "Geräteinstallation erfordert Apple Signierung.");

  var table = document.getElementById("sums");
  Object.keys(r.files).forEach(function (f) {
    var tr = document.createElement("tr");
    tr.innerHTML = "<td>" + f + "</td><td><code>" + r.files[f].sha256 + "</code></td>";
    table.appendChild(tr);
  });
})();
