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

    boolean receive(Object owner, Object eventId) {
        if (!valid(owner) || !valid(eventId)) return false;
        pending = new HashMap<>();
        pending.put("owner", (String) owner);
        pending.put("eventId", (String) eventId);
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
