package dev.pocketworld.sharedviewerfixture;

import android.app.Activity;
import android.content.Intent;
import android.database.Cursor;
import android.net.Uri;
import android.os.Bundle;
import android.provider.OpenableColumns;
import android.webkit.WebView;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import java.io.ByteArrayOutputStream;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import org.json.JSONObject;

/** Separate user-operated fixture. No production bundle ID or user-record API. */
public final class MainActivity extends Activity implements ViewerHost.Listener {
    private ViewerHost host;
    private TextView status;
    private boolean destroyed;
    private final ExecutorService io = Executors.newSingleThreadExecutor();
    @Override public void onCreate(Bundle saved) {
        super.onCreate(saved);
        LinearLayout column = new LinearLayout(this);
        column.setOrientation(LinearLayout.VERTICAL);
        column.setBackgroundColor(0xff000000);
        status = new TextView(this);
        status.setTextColor(0xffffffff);
        status.setText("Initializing shared renderer");
        column.addView(status);
        Button choose = new Button(this);
        choose.setText("Open GLB / PLY / SKP");
        choose.setOnClickListener(view -> {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION);
            intent.setType("*/*");
            startActivityForResult(intent, 1);
        });
        column.addView(choose);
        WebView view = new WebView(this);
        column.addView(view, new LinearLayout.LayoutParams(-1, 0, 1));
        setContentView(column);
        host = new ViewerHost(this, view, this);
        host.start();
    }
    @Override public void onReady() {
        status.setText("Shared renderer ready: " + BundleAssets.IDENTITY);
        byte[] triangle = ("ply\nformat ascii 1.0\nelement vertex 3\nproperty float x\nproperty float y\nproperty float z\n" +
            "element face 1\nproperty list uchar int vertex_indices\nend_header\n0 0 0\n1 0 0\n0 1 0\n3 0 1 2\n").getBytes(StandardCharsets.UTF_8);
        load(triangle, "ply");
    }
    @Override public void onPacket(String packet) {
        try {
            JSONObject decoded = new JSONObject(packet);
            JSONObject state = decoded.optJSONObject("state");
            if (state != null && !state.optString("error").isEmpty() && !state.isNull("error")) status.setText(state.optString("error"));
        } catch (Exception ignored) {}
    }
    @Override public void onError(String error) { if (!destroyed) status.setText("ERROR: " + error); }
    private void load(byte[] bytes, String format) {
        if (destroyed) return;
        if (!host.isReady()) { onError("Renderer is not ready"); return; }
        final String url = host.registerModel(bytes, format);
        loadRegistered(url, format);
    }
    private void loadDocument(Uri uri, String format) {
        if (destroyed) return;
        if (!host.isReady()) { onError("Renderer is not ready"); return; }
        try { loadRegistered(host.registerDocument(uri, format), format); }
        catch (Exception failed) { onError("Selected document read grant unavailable"); }
    }
    private void loadRegistered(String url, String format) {
        try {
            host.request("load", new JSONObject().put("url", url).put("format", format), (packet, error) -> {
                if (destroyed) return;
                status.setText(error == null ? "Loaded " + format.toUpperCase(Locale.ROOT) + " / " + BundleAssets.IDENTITY : error);
                // Loader has consumed the source; release private input bytes.
                host.unregisterModel(url);
            });
        } catch (Exception failed) { host.unregisterModel(url); onError("Model request failed"); }
    }
    @Override protected void onActivityResult(int request, int result, Intent data) {
        super.onActivityResult(request, result, data);
        if (request != 1 || result != RESULT_OK || data == null || data.getData() == null) return;
        final Uri uri = data.getData();
        io.execute(() -> {
            try {
                String name = "";
                try (Cursor cursor = getContentResolver().query(uri, new String[]{OpenableColumns.DISPLAY_NAME}, null, null, null)) {
                    if (cursor != null && cursor.moveToFirst()) name = cursor.getString(0);
                }
                String lower = name.toLowerCase(Locale.ROOT);
                String format = lower.substring(lower.lastIndexOf('.') + 1);
                if (!HostPolicy.formatAllowed(format)) throw new IllegalArgumentException("Choose .glb, .ply or .skp");
                if (!"skp".equals(format)) {
                    runOnUiThread(() -> loadDocument(uri, format));
                    return;
                }
                byte[] bytes;
                try (InputStream input = getContentResolver().openInputStream(uri); ByteArrayOutputStream out = new ByteArrayOutputStream()) {
                    if (input == null) throw new IllegalArgumentException("Cannot read chosen file");
                    byte[] buffer = new byte[65536];
                    int count;
                    while ((count = input.read(buffer)) != -1) {
                        if (out.size() + count > 32 * 1024 * 1024) throw new IllegalArgumentException("SKP import limit is 32 MiB; export GLB for larger sources");
                        out.write(buffer, 0, count);
                    }
                    bytes = out.toByteArray();
                }
                runOnUiThread(() -> load(bytes, format));
            } catch (Exception failed) {
                final String error = failed.getMessage() == null ? "Unable to open selected model" : failed.getMessage();
                runOnUiThread(() -> onError(error));
            }
        });
    }
    @Override protected void onResume() { super.onResume(); if (host != null) host.setForeground(true); }
    @Override protected void onPause() { if (host != null) host.setForeground(false); super.onPause(); }
    @Override protected void onDestroy() {
        destroyed = true;
        if (host != null) host.dispose();
        io.shutdownNow();
        super.onDestroy();
    }
}
