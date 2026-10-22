package com.example.south_plus_rewrite;

import java.util.Map;

public final class WatchNotificationTapStateCheck {
    public static void main(String[] args) {
        WatchNotificationTapState state = new WatchNotificationTapState();
        assert state.take() == null;
        String customOwner = "https://forum.example:account:synthetic%20name";
        assert state.receive(customOwner, "rule/topics/701");
        Map<String, String> cold = state.take();
        assert cold.get("owner").equals(customOwner);
        assert cold.get("eventId").equals("rule/topics/701");
        assert cold.size() == 2 : "only opaque lookup keys cross the bridge";
        assert state.take() == null : "cold tap is consumed once";
        assert state.receive("synthetic-owner", "rule/replies/801");
        assert state.receive("synthetic-owner", "rule/replies/802");
        assert state.take().get("eventId").equals("rule/replies/802") : "warm tap replaces pending";
        assert state.take() == null;
        for (Object invalid : new Object[] {null, 7, "", "x".repeat(1025), "bad\nkey", "bad\u0000key", "bad\u202Ekey"}) {
            assert !state.receive(invalid, "rule/topics/701");
            assert !state.receive("synthetic-owner", invalid);
            assert state.take() == null : "invalid payload must not reach Dart";
        }
        assert state.receive("x".repeat(1024), "y".repeat(1024));
        state.clear();
        assert state.take() == null : "actual account switch cancels pending navigation";
        System.out.println("WatchNotificationTapStateCheck PASS");
    }
}
