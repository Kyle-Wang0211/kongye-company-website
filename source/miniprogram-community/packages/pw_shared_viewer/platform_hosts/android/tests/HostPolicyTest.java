package dev.pocketworld.sharedviewerfixture;

import java.util.Arrays;
import java.util.HashSet;
import java.util.Set;

/** Runs the actual pure host routing policy on the JVM; no Android runtime claim. */
public final class HostPolicyTest {
    private static void check(boolean condition, String name) {
        if (!condition) throw new AssertionError(name);
    }
    public static void main(String[] args) {
        Set<String> assets = new HashSet<>(Arrays.asList("index.html", "viewer.mjs", "skp_import_worker.mjs", "vendor/openskp/openskp-browser.mjs"));
        check(HostPolicy.navigationAllowed(HostPolicy.ENTRY, true), "entry main navigation");
        check(!HostPolicy.navigationAllowed(HostPolicy.ENTRY, false), "frame denied");
        for (String url : Arrays.asList("http://pw-viewer.invalid/index.html", "https://pw-viewer.invalid:443/index.html",
                "https://pw-viewer.invalid.evil/index.html", "https://pw-viewer.invalid@evil/index.html",
                "https://pw-viewer.invalid/%2e%2e/index.html", "https://pw-viewer.invalid/../index.html",
                "https://pw-viewer.invalid/index.html?extra=1", "https://pw-viewer.invalid/index.html#fragment",
                "file:///etc/passwd", "content://private/model", "javascript:alert(1)", "data:text/html,hello")) {
            check(!HostPolicy.navigationAllowed(url, true), "navigation denied: " + url);
            check(HostPolicy.assetPath(url, assets) == null, "resource denied: " + url);
        }
        for (String asset : assets) check(asset.equals(HostPolicy.assetPath(HostPolicy.ORIGIN + "/" + asset, assets)), "resource allowlist: " + asset);
        check(HostPolicy.assetPath(HostPolicy.ORIGIN + "/missing.mjs", assets) == null, "unknown resource denied");
        check("text/javascript".equals(HostPolicy.mime("skp_import_worker.mjs")), "module MIME");
        for (String format : Arrays.asList("glb", "ply", "skp")) check(HostPolicy.formatAllowed(format), "model format: " + format);
        check(!HostPolicy.formatAllowed("obj") && !HostPolicy.formatAllowed(null), "unknown model format denied");
        for (String method : Arrays.asList("load", "getState", "resize", "capture", "pause", "resume", "dispose")) check(HostPolicy.methodAllowed(method), "method: " + method);
        check(!HostPolicy.methodAllowed("eval") && !HostPolicy.methodAllowed(null), "unknown method denied");
        System.out.println("HOST_POLICY_PASS: routing, origins, frames, resources, MIME, formats and methods");
    }
}
