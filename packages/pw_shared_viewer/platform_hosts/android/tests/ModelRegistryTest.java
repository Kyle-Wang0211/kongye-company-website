package dev.pocketworld.sharedviewerfixture;

import java.io.IOException;
import java.io.InputStream;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.concurrent.atomic.AtomicReference;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;

public final class ModelRegistryTest {
    private static void check(boolean value, String reason) { if (!value) throw new AssertionError(reason); }
    private static void await(CountDownLatch latch, String reason) throws Exception {
        check(latch.await(2, TimeUnit.SECONDS), reason);
    }
    private static void joined(Thread thread, String reason) throws Exception {
        thread.join(2000);
        check(!thread.isAlive(), reason);
    }
    private static void blockedOpener(boolean closeRegistry) throws Exception {
        ModelRegistry registry = new ModelRegistry();
        CountDownLatch opening = new CountDownLatch(1), release = new CountDownLatch(1);
        CountDownLatch rawClosed = new CountDownLatch(1), callerReturned = new CountDownLatch(1);
        AtomicReference<InputStream> published = new AtomicReference<>();
        AtomicReference<Throwable> openingFailure = new AtomicReference<>();
        AtomicReference<Thread> cleanupThread = new AtomicReference<>();
        String url = registry.register("glb", () -> {
            opening.countDown();
            try { if (!release.await(5, TimeUnit.SECONDS)) throw new IOException("Opener release timed out"); }
            catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); throw new IOException(interrupted); }
            return new InputStream() {
                @Override public int read() { return -1; }
                @Override public void close() { cleanupThread.set(Thread.currentThread()); rawClosed.countDown(); }
            };
        });
        Thread opener = new Thread(() -> {
            try { published.set(registry.open(url)); } catch (Throwable failure) { openingFailure.set(failure); }
        }, "test-blocked-opener");
        Thread caller = new Thread(() -> {
            if (closeRegistry) registry.close(); else registry.unregister(url);
            callerReturned.countDown();
        }, "test-revoke-during-open");
        opener.setDaemon(true); caller.setDaemon(true);
        try {
            opener.start();
            await(opening, "source opener entered");
            caller.start();
            await(callerReturned, "UI revocation must return while provider open is blocked");
            check(!registry.contains(url), "blocked source mapping removed immediately");
            release.countDown();
            joined(opener, "opener thread finished");
            check(published.get() == null && openingFailure.get() instanceof IOException, "late opened stream must never be published after revocation");
            await(rawClosed, "late opened raw stream closed");
            check(cleanupThread.get() != caller && cleanupThread.get() != opener, "late-open cleanup runs on a separate thread");
            joined(cleanupThread.get(), "late-open cleanup thread finished");
            joined(caller, "revocation caller finished");
        } finally {
            release.countDown();
            opener.join(2000); caller.join(2000);
            registry.close();
        }
    }
    private static void blockedCloser(boolean closeRegistry) throws Exception {
        ModelRegistry registry = new ModelRegistry();
        CountDownLatch closing = new CountDownLatch(1), release = new CountDownLatch(1);
        CountDownLatch rawClosed = new CountDownLatch(1), callerReturned = new CountDownLatch(1);
        AtomicReference<Thread> cleanupThread = new AtomicReference<>();
        String url = registry.register("ply", () -> new InputStream() {
            @Override public int read() { return -1; }
            @Override public void close() throws IOException {
                cleanupThread.set(Thread.currentThread());
                closing.countDown();
                try { if (!release.await(5, TimeUnit.SECONDS)) throw new IOException("Closer release timed out"); }
                catch (InterruptedException interrupted) { Thread.currentThread().interrupt(); throw new IOException(interrupted); }
                finally { rawClosed.countDown(); }
            }
        });
        InputStream stream = registry.open(url);
        Thread caller = new Thread(() -> {
            if (closeRegistry) registry.close(); else registry.unregister(url);
            callerReturned.countDown();
        }, "test-revoke-during-close");
        caller.setDaemon(true);
        try {
            caller.start();
            await(closing, "provider close entered");
            await(callerReturned, "UI revocation must return while provider close is blocked");
            check(!registry.contains(url), "mapping absent while raw close is blocked");
            try { stream.read(); throw new AssertionError("revoked stream remained readable"); }
            catch (IOException expected) {}
            check(cleanupThread.get() != caller, "raw provider close must run off caller thread");
            release.countDown();
            await(rawClosed, "raw close completed after release");
            joined(cleanupThread.get(), "provider cleanup thread finished");
            joined(caller, "close caller finished");
        } finally {
            release.countDown(); caller.join(2000); registry.close();
        }
    }
    public static void main(String[] args) throws Exception {
        ModelRegistry registry = new ModelRegistry();
        AtomicInteger opens = new AtomicInteger();
        final long length = 77L * 1024 * 1024;
        String url = registry.register("glb", () -> {
            opens.incrementAndGet();
            return new InputStream() {
                long remaining = length;
                @Override public int read() { if (remaining == 0) return -1; remaining--; return 7; }
                @Override public int read(byte[] b, int offset, int count) {
                    if (remaining == 0) return -1;
                    int n = (int) Math.min(count, remaining);
                    remaining -= n;
                    return n;
                }
            };
        });
        check(opens.get() == 0, "registration must not read or open the model");
        check(registry.contains(url) && url.startsWith(HostPolicy.ORIGIN + "/models/") && url.endsWith(".glb"), "opaque GLB URL schema");
        try (InputStream input = registry.open(url)) {
            byte[] chunk = new byte[8192];
            long total = 0;
            int n;
            while ((n = input.read(chunk)) != -1) total += n;
            check(total == length, "77 MiB source streams with a fixed-size buffer");
        }
        check(opens.get() == 1, "one open per request");
        InputStream active = registry.open(url);
        registry.unregister(url);
        check(!registry.contains(url) && registry.open(url) == null, "unregister drops source mapping");
        try { active.read(); throw new AssertionError("unregister must revoke open stream"); }
        catch (IOException expected) {}
        check(registry.open("file:///private/model.glb") == null, "no arbitrary local path mapping");
        check(registry.open(HostPolicy.ORIGIN + "/models/999.glb") == null, "unregistered URL denied");
        try { registry.register("obj", () -> null); throw new AssertionError("invalid format accepted"); }
        catch (IllegalArgumentException expected) {}
        for (String format : new String[]{"ply", "skp"}) {
            String model = registry.register(format, () -> new java.io.ByteArrayInputStream(new byte[]{1}));
            check(model.endsWith("." + format), "format schema " + format);
        }
        registry.close();
        check(registry.open(url) == null, "close drops all mappings");
        try { registry.register("glb", () -> null); throw new AssertionError("closed registry accepted registration"); }
        catch (IllegalArgumentException expected) {}
        blockedOpener(false);
        blockedOpener(true);
        blockedCloser(false);
        blockedCloser(true);
        System.out.println("MODEL_REGISTRY_PASS: blocked open/close revocation and cleanup threads; lazy source registration, 77 MiB streaming under a 32 MiB JVM heap, revocation and format schema");
    }
}
