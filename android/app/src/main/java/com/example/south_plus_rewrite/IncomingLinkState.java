package com.example.south_plus_rewrite;

import java.net.URI;
import java.net.URISyntaxException;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

final class IncomingLinkState {
    private static final String[] HOSTS = {
        "east-plus.net", "south-plus.net", "south-plus.org", "white-plus.net",
        "north-plus.net", "level-plus.net", "soul-plus.net", "snow-plus.net",
        "spring-plus.net", "summer-plus.net", "blue-plus.net", "imoutolove.me"
    };
    private long sequence;
    private boolean consumed;
    private String pendingUrl;

    IncomingLinkState(long sequence, boolean consumed) {
        this.sequence = sequence;
        this.consumed = consumed;
    }

    void restore(String url) {
        if (consumed) return;
        if (sequence == 0) sequence = 1;
        pendingUrl = safeUrl(url);
    }

    void receive(String url) {
        sequence++;
        consumed = false;
        pendingUrl = safeUrl(url);
    }

    void acknowledge(long id) {
        if (id != sequence) return;
        consumed = true;
        pendingUrl = null;
    }

    long sequence() { return sequence; }
    boolean consumed() { return consumed; }

    Map<String, Object> pending() {
        if (pendingUrl == null) return null;
        Map<String, Object> event = new HashMap<>();
        event.put("id", sequence);
        event.put("url", pendingUrl);
        return event;
    }

    private static String safeUrl(String raw) {
        if (raw == null || raw.length() > 8192) return "";
        try {
            URI uri = new URI(raw);
            String scheme = uri.getScheme();
            int expectedPort;
            if ("https".equalsIgnoreCase(scheme)) expectedPort = 443;
            else if ("http".equalsIgnoreCase(scheme)) expectedPort = 80;
            else return "";
            if (uri.getRawUserInfo() != null || (uri.getPort() != -1 && uri.getPort() != expectedPort)) return "";
            String host = uri.getHost();
            if (host == null) return "";
            host = host.toLowerCase(Locale.ROOT);
            if (host.endsWith(".")) host = host.substring(0, host.length() - 1);
            for (String alias : HOSTS) {
                if (host.equals(alias) || host.endsWith("." + alias)) return raw;
            }
        } catch (URISyntaxException ignored) {
            // Rejection crosses the bridge without the untrusted URL.
        }
        return "";
    }
}
