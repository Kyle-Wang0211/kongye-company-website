package dev.pocketworld.sharedviewerfixture;

import java.io.Closeable;
import java.io.FilterInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.util.HashSet;
import java.util.Set;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

/** Opaque model URLs backed by explicitly authorized source factories, without eager reads. */
public final class ModelRegistry implements Closeable {
    public interface StreamFactory { InputStream open() throws IOException; }
    private final ConcurrentHashMap<String, Source> sources = new ConcurrentHashMap<>();
    private final AtomicLong serial = new AtomicLong();
    private boolean closed;

    // A provider may block indefinitely in close(). Never run that I/O while
    // holding registry/source monitors or on the UI revocation caller.
    private static void closeOffThread(InputStream raw) {
        Thread cleanup = new Thread(() -> {
            try { raw.close(); } catch (IOException | RuntimeException ignored) {}
        }, "pw-model-stream-close");
        cleanup.setDaemon(true);
        cleanup.start();
    }
    private static final class Source implements Closeable {
        final StreamFactory factory;
        final Set<ManagedStream> streams = new HashSet<>();
        boolean revoked;
        Source(StreamFactory factory) { this.factory = factory; }
        InputStream open() throws IOException {
            synchronized (this) {
                if (revoked) throw new IOException("Model source revoked");
            }
            // Content providers perform I/O here. Revocation must not wait for it.
            InputStream raw = factory.open();
            if (raw == null) throw new IOException("Model source unavailable");
            ManagedStream stream = new ManagedStream(raw, this);
            synchronized (this) {
                if (!revoked) {
                    streams.add(stream);
                    return stream;
                }
            }
            // The source was revoked while its provider was opening. Do not
            // publish late bytes; cleanup also stays off this lock/caller.
            stream.close();
            throw new IOException("Model source revoked while opening");
        }
        synchronized void forget(ManagedStream stream) { streams.remove(stream); }
        @Override public void close() {
            ManagedStream[] active;
            synchronized (this) {
                if (revoked) return;
                revoked = true;
                active = streams.toArray(new ManagedStream[0]);
                streams.clear();
            }
            for (ManagedStream stream : active) stream.close();
        }
    }
    private static final class ManagedStream extends FilterInputStream {
        final Source source;
        final AtomicBoolean streamClosed = new AtomicBoolean();
        ManagedStream(InputStream raw, Source source) { super(raw); this.source = source; }
        private void availableOrThrow() throws IOException {
            if (streamClosed.get()) throw new IOException("Model stream closed");
        }
        @Override public int read() throws IOException { availableOrThrow(); return super.read(); }
        @Override public int read(byte[] bytes, int offset, int length) throws IOException {
            availableOrThrow(); return super.read(bytes, offset, length);
        }
        @Override public void close() {
            if (!streamClosed.compareAndSet(false, true)) return;
            source.forget(this);
            closeOffThread(in);
        }
    }
    public synchronized String register(String format, StreamFactory source) {
        if (closed || !HostPolicy.formatAllowed(format) || source == null) throw new IllegalArgumentException("Invalid model source/format");
        String url = HostPolicy.ORIGIN + "/models/" + serial.incrementAndGet() + "." + format;
        sources.put(url, new Source(source));
        return url;
    }
    public boolean contains(String url) { return sources.containsKey(url); }
    public InputStream open(String url) throws IOException {
        Source source = sources.get(url);
        return source == null ? null : source.open();
    }
    public void unregister(String url) {
        Source source = sources.remove(url);
        if (source != null) source.close();
    }
    @Override public synchronized void close() {
        if (closed) return;
        closed = true;
        for (Source source : sources.values()) source.close();
        sources.clear();
    }
}
