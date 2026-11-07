package dev.pocketworld.sharedviewerfixture;

import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;

/** Pure routing policy, usable in host-JVM tests without Android framework stubs. */
public final class HostPolicy {
    public static final String ORIGIN = "https://pw-viewer.invalid";
    public static final String ENTRY = ORIGIN + "/index.html";
    public static final String PROTOCOL = "PW_SHARED_VIEWER_V1";
    private static final Set<String> METHODS = Collections.unmodifiableSet(new HashSet<>(
        Arrays.asList("getCameraFraming", "setCameraFraming", "setDownloadProgress", "load", "resize", "capture", "pause", "resume", "dispose", "getState", "configure", "resetCamera", "setSurfaceCommentMode", "setSurfaceCommentMarkers", "focusSurfaceComment", "beginSelectionEditing", "endSelectionEditing", "getSelectionView", "setSelectionView", "getSelectionBounds", "setSelectionPreview")));
    private HostPolicy() {}
    public static boolean navigationAllowed(String url, boolean mainFrame) {
        return mainFrame && ENTRY.equals(url);
    }
    public static boolean methodAllowed(String method) { return METHODS.contains(method); }
    public static boolean formatAllowed(String format) {
        return "glb".equals(format) || "ply".equals(format) || "skp".equals(format);
    }
    public static String assetPath(String url, Set<String> assets) {
        if (url == null || !url.startsWith(ORIGIN + "/")) return null;
        String path = url.substring(ORIGIN.length() + 1);
        return assets.contains(path) ? path : null;
    }
    public static String mime(String path) {
        if (path.endsWith(".html")) return "text/html";
        if (path.endsWith(".mjs") || path.endsWith(".js")) return "text/javascript";
        if (path.endsWith(".json")) return "application/json";
        if (path.endsWith(".glb")) return "model/gltf-binary";
        if (path.endsWith(".wasm")) return "application/wasm";
        return "application/octet-stream";
    }
}
