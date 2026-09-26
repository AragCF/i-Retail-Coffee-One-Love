package com.coffeeonelove.iretail.ui;

/** One active read per owner. Invalidation rejects the result, not the running I/O. */
public final class ApiRequestGate {
    private long sequence;
    private long generation;
    private long activeTicket;
    private long activeGeneration;
    private boolean closed;

    public synchronized Long tryBegin() {
        if (closed || activeTicket != 0L) return null;
        activeTicket = ++sequence;
        activeGeneration = generation;
        return activeTicket;
    }

    /** A foreign or repeated completion must not release a newer request. */
    public synchronized boolean complete(long ticket) {
        if (ticket == 0L || ticket != activeTicket) return false;
        boolean accepted = !closed && activeGeneration == generation;
        activeTicket = 0L;
        return accepted;
    }

    /** Keep the occupied slot until the running read actually returns. */
    public synchronized void invalidate() {
        generation++;
    }

    public synchronized void close() {
        closed = true;
        generation++;
    }
}
