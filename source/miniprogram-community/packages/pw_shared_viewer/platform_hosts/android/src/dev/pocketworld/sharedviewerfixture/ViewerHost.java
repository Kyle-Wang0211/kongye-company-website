package dev.pocketworld.sharedviewerfixture;

import android.annotation.SuppressLint;
import android.content.Context;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.net.Uri;
import android.os.Process;
import android.graphics.Bitmap;
import android.net.http.SslError;
import android.os.Handler;
import android.os.Looper;
import android.webkit.JavascriptInterface;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.SslErrorHandler;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import android.view.ViewGroup;
import android.view.ViewParent;
import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.HashMap;
import java.util.Map;
import org.json.JSONException;
import org.json.JSONObject;

/** Native WebView transport only. All rendering and SKP conversion stay in shared assets. */
public final class ViewerHost {
    public interface Listener {
        void onReady();
        void onPacket(String packet);
        void onError(String error);
    }
    public interface Reply { void complete(String packet, String error); }
    private static final String CSP = "default-src 'none'; script-src 'self' 'unsafe-inline'; " +
        "style-src 'unsafe-inline'; connect-src 'self'; img-src 'self' data: blob:; " +
        "worker-src 'self' blob:; frame-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'";
    private final Context context;
    private final WebView view;
    private final Listener listener;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ModelRegistry models = new ModelRegistry();
    private final Map<String, Pending> pending = new HashMap<>();
    private boolean ready, foreground = true, pageActive;
    private volatile boolean dead;
    private long requestSerial;
    private static final class Pending {
        final Reply callback;
        final Runnable timeout;
        Pending(Reply callback, Runnable timeout) { this.callback = callback; this.timeout = timeout; }
    }

    @SuppressLint("SetJavaScriptEnabled")
    public ViewerHost(Context context, WebView view, Listener listener) {
        this.context = context;
        this.view = view;
        this.listener = listener;
        WebSettings settings = view.getSettings();
        settings.setJavaScriptEnabled(true);
        settings.setAllowFileAccess(false);
        settings.setAllowContentAccess(false);
        settings.setAllowFileAccessFromFileURLs(false);
        settings.setAllowUniversalAccessFromFileURLs(false);
        settings.setDomStorageEnabled(false);
        settings.setDatabaseEnabled(false);
        settings.setMixedContentMode(WebSettings.MIXED_CONTENT_NEVER_ALLOW);
        settings.setSupportMultipleWindows(false);
        settings.setJavaScriptCanOpenWindowsAutomatically(false);
        settings.setCacheMode(WebSettings.LOAD_NO_CACHE);
        // Network fallback is forbidden independently of interception/CSP. Asset
        // responses still come from shouldInterceptRequest; verify on a device.
        settings.setBlockNetworkLoads(true);
        view.setBackgroundColor(0xff000000);
        view.addJavascriptInterface(new NativeChannel(), "PWSharedHost");
        view.setWebViewClient(new WebViewClient() {
            @Override public boolean shouldOverrideUrlLoading(WebView web, WebResourceRequest request) {
                return !HostPolicy.navigationAllowed(request.getUrl().toString(), request.isForMainFrame());
            }
            @Override public boolean shouldOverrideUrlLoading(WebView web, String url) {
                return !HostPolicy.navigationAllowed(url, true);
            }
            @Override public WebResourceResponse shouldInterceptRequest(WebView web, WebResourceRequest request) {
                return intercept(request.getUrl().toString(), request.getMethod());
            }
            @Override public void onPageStarted(WebView web, String url, Bitmap icon) {
                ready = false;
                pageActive = HostPolicy.ENTRY.equals(url) && !dead;
                rejectPending("Viewer document changed");
            }
            @Override public void onPageFinished(WebView web, String url) {
                if (dead || !HostPolicy.ENTRY.equals(url)) return;
                pageActive = true;
                web.evaluateJavascript("window.pwSharedViewerReady.then(() => window.PWSharedBridge.request({id:'host-ready',method:'getState',args:{}})).catch(() => {});", null);
            }
            @Override public void onReceivedError(WebView web, WebResourceRequest request, WebResourceError error) {
                if (request.isForMainFrame()) fail("WebView document load failed");
            }
            @Override public void onReceivedHttpError(WebView web, WebResourceRequest request, WebResourceResponse error) {
                if (request.isForMainFrame()) fail("WebView document HTTP failure");
            }
            @Override public void onReceivedSslError(WebView web, SslErrorHandler handler, SslError error) {
                handler.cancel();
                fail("Unexpected network/TLS access denied");
            }
            @Override public boolean onRenderProcessGone(WebView web, RenderProcessGoneDetail detail) {
                fail("WebView renderer exited; recreate the fixture");
                dispose();
                return true;
            }
        });
    }

    public void start() { checkMain(); if (!dead) view.loadUrl(HostPolicy.ENTRY); }
    public boolean isReady() { return ready && !dead; }
    private void checkMain() {
        if (Looper.myLooper() != Looper.getMainLooper()) throw new IllegalStateException("Viewer API requires UI thread");
    }
    public String registerModel(byte[] bytes, String format) {
        checkMain();
        if (dead || bytes == null || bytes.length == 0 || !HostPolicy.formatAllowed(format)) {
            throw new IllegalArgumentException("Expected nonempty GLB, PLY or SKP bytes");
        }
        final byte[] frozen = bytes.clone();
        return models.register(format, () -> new ByteArrayInputStream(frozen));
    }
    // Only SAF-selected content URIs with a live explicit read grant are accepted.
    // The source stays in the provider; interception opens a bounded streaming read.
    public String registerDocument(Uri uri, String format) {
        checkMain();
        if (dead || uri == null || !"content".equals(uri.getScheme()) ||
                !HostPolicy.formatAllowed(format) ||
                context.checkUriPermission(uri, Process.myPid(), Process.myUid(),
                    Intent.FLAG_GRANT_READ_URI_PERMISSION) != PackageManager.PERMISSION_GRANTED) {
            throw new IllegalArgumentException("A selected document read grant is required");
        }
        return models.register(format, () -> context.getContentResolver().openInputStream(uri));
    }
    public void unregisterModel(String url) { checkMain(); models.unregister(url); }

    private WebResourceResponse response(int code, String mime, InputStream stream) {
        Map<String, String> headers = new HashMap<>();
        headers.put("X-Content-Type-Options", "nosniff");
        headers.put("Cache-Control", "no-store");
        headers.put("Content-Security-Policy", CSP);
        return new WebResourceResponse(mime, "UTF-8", code, code == 200 ? "OK" : "Unavailable", headers, stream);
    }
    private WebResourceResponse intercept(String url, String method) {
        // Invoked off the UI thread. Concurrent model snapshots are immutable.
        if (dead) return response(404, "text/plain", new ByteArrayInputStream(new byte[0]));
        if (!"GET".equals(method)) return response(405, "text/plain", new ByteArrayInputStream(new byte[0]));
        try {
            InputStream model = models.open(url);
            if (model != null) return response(200, HostPolicy.mime(url), model);
        } catch (IOException | SecurityException unavailable) {
            return response(500, "text/plain", new ByteArrayInputStream(new byte[0]));
        }
        String asset = HostPolicy.assetPath(url, BundleAssets.PATHS);
        if (asset != null) {
            try { return response(200, HostPolicy.mime(asset), context.getAssets().open("pw_shared_viewer/" + asset)); }
            catch (IOException failure) { return response(500, "text/plain", new ByteArrayInputStream(new byte[0])); }
        }
        return response(404, "text/plain", new ByteArrayInputStream(new byte[0]));
    }

    public final class NativeChannel {
        @JavascriptInterface public void postMessage(String packet) {
            if (packet == null || packet.length() > 64 * 1024 * 1024) return;
            main.post(() -> receive(packet));
        }
    }
    private void receive(String message) {
        if (dead || !pageActive || !HostPolicy.ENTRY.equals(view.getUrl())) return;
        try {
            JSONObject packet = new JSONObject(message);
            if (!HostPolicy.PROTOCOL.equals(packet.optString("protocol"))) return;
            boolean readyEvent = "pw-viewer-ready".equals(packet.optString("type"));
            boolean handshake = "host-ready".equals(packet.optString("id")) && packet.optBoolean("ok");
            if (readyEvent || handshake) {
                JSONObject state = packet.optJSONObject(readyEvent ? "state" : "result");
                if (state == null || !BundleAssets.IDENTITY.equals(state.optString("bundleIdentity"))) {
                    fail("Viewer bundle identity does not match packaged resources");
                    return;
                }
                boolean first = !ready;
                ready = true;
                if (!foreground) request("pause", new JSONObject(), null);
                if (first) listener.onReady();
            }
            Pending request = pending.remove(packet.optString("id"));
            if (request != null) {
                main.removeCallbacks(request.timeout);
                if (request.callback != null) request.callback.complete(message,
                    packet.optBoolean("ok") ? null : "Viewer request failed");
            }
            listener.onPacket(message);
        } catch (JSONException invalid) { /* Ignore untrusted malformed packets. */ }
    }

    public void request(String method, JSONObject args, Reply callback) {
        checkMain();
        if (!isReady() || !HostPolicy.methodAllowed(method)) {
            if (callback != null) callback.complete(null, "Viewer unavailable or invalid method");
            return;
        }
        if (args == null) args = new JSONObject();
        if ("load".equals(method)) {
            String url = args.optString("url"), format = args.optString("format");
            if (!models.contains(url) || !HostPolicy.formatAllowed(format) || !url.endsWith("." + format)) {
                if (callback != null) callback.complete(null, "Load requires a registered GLB, PLY or SKP");
                return;
            }
        }
        String id = "android-" + (++requestSerial);
        JSONObject packet = new JSONObject();
        try { packet.put("id", id).put("method", method).put("args", args); }
        catch (JSONException invalid) { if (callback != null) callback.complete(null, "Invalid request"); return; }
        Runnable timeout = () -> {
            Pending failed = pending.remove(id);
            if (failed != null && failed.callback != null) failed.callback.complete(null, "Viewer request timed out");
        };
        pending.put(id, new Pending(callback, timeout));
        main.postDelayed(timeout, 90000);
        try { view.evaluateJavascript("window.PWSharedBridge.request(" + packet.toString() + ").catch(() => {});", null); }
        catch (RuntimeException failed) {
            Pending removed = pending.remove(id);
            main.removeCallbacks(timeout);
            if (removed != null && callback != null) callback.complete(null, "WebView dispatch failed");
        }
    }
    public void setForeground(boolean value) {
        checkMain();
        foreground = value;
        if (!dead) {
            if (value) view.onResume();
            if (isReady()) request(value ? "resume" : "pause", new JSONObject(), null);
            if (!value) view.onPause();
        }
    }
    private void rejectPending(String reason) {
        Pending[] requests = pending.values().toArray(new Pending[0]);
        pending.clear();
        for (Pending request : requests) {
            main.removeCallbacks(request.timeout);
            if (request.callback != null) request.callback.complete(null, reason);
        }
    }
    private void fail(String reason) {
        ready = false;
        pageActive = false;
        rejectPending(reason);
        listener.onError(reason);
    }
    public void dispose() {
        checkMain();
        if (dead) return;
        dead = true;
        ready = false;
        pageActive = false;
        rejectPending("Viewer disposed");
        models.close();
        try { view.evaluateJavascript("window.pwSharedViewerController?.dispose();", null); } catch (RuntimeException ignored) {}
        view.removeJavascriptInterface("PWSharedHost");
        view.stopLoading();
        ViewParent parent = view.getParent();
        if (parent instanceof ViewGroup) ((ViewGroup) parent).removeView(view);
        view.destroy();
    }
}
