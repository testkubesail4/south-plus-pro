package com.example.south_plus_rewrite;

import java.util.HashMap;
import java.util.Map;

final class WatchNotificationTapState {
    private Map<String, String> pending;

    static boolean valid(Object value) {
        if (!(value instanceof String)) return false;
        String text = (String) value;
        return !text.isEmpty() && text.length() <= 1024
            && text.codePoints().noneMatch(point -> Character.isISOControl(point)
                || Character.getType(point) == Character.FORMAT);
    }

    static String kind(Object value) {
        if (value == null) return "watch";
        return "watch".equals(value) || "pm".equals(value) || "reply".equals(value)
            ? (String) value : null;
    }

    boolean receive(Object owner, Object eventId, Object kind) {
        String type = kind(kind);
        if (!valid(owner) || !valid(eventId) || type == null) return false;
        pending = new HashMap<>();
        pending.put("owner", (String) owner);
        pending.put("eventId", (String) eventId);
        pending.put("kind", type);
        return true;
    }

    Map<String, String> take() {
        Map<String, String> result = pending;
        clear();
        return result;
    }

    void clear() {
        pending = null;
    }
}
