package com.example.south_plus_rewrite;

import java.util.Map;

public final class WatchNotificationTapStateCheck {
    public static void main(String[] args) {
        WatchNotificationTapState state = new WatchNotificationTapState();
        assert state.take() == null;
        String customOwner = "https://forum.example:account:synthetic%20name";
        assert state.receive(customOwner, "rule/topics/701", null);
        Map<String, String> cold = state.take();
        assert cold.get("owner").equals(customOwner);
        assert cold.get("eventId").equals("rule/topics/701");
        assert cold.get("kind").equals("watch") : "legacy pending intents retain watch routing";
        assert cold.size() == 3 : "only opaque lookup keys and the validated kind cross the bridge";
        assert state.take() == null : "cold tap is consumed once";
        for (String kind : new String[] {"watch", "pm", "reply"}) {
            assert state.receive("synthetic-owner", "fixture/801", kind);
            assert state.receive("synthetic-owner", "fixture/802", kind);
            Map<String, String> warm = state.take();
            assert warm.get("eventId").equals("fixture/802") : "warm tap replaces pending";
            assert warm.get("kind").equals(kind);
            assert state.take() == null;
        }
        for (Object invalid : new Object[] {null, 7, "", "x".repeat(1025), "bad\nkey", "bad\u0000key", "bad\u202Ekey"}) {
            assert !state.receive(invalid, "rule/topics/701", "pm");
            assert !state.receive("synthetic-owner", invalid, "reply");
            assert state.take() == null : "invalid payload must not reach Dart";
        }
        for (Object invalidKind : new Object[] {7, "", "PM", "topic", "pm\n", "https://forum.example"}) {
            assert state.receive("synthetic-owner", "fixture/803", "pm");
            assert !state.receive("synthetic-owner", "fixture/804", invalidKind);
            assert state.take().get("eventId").equals("fixture/803")
                : "invalid kind must neither route nor replace an already-clicked tap";
        }
        assert state.receive("x".repeat(1024), "y".repeat(1024), "reply");
        state.clear();
        assert state.take() == null : "actual account switch cancels pending navigation";
        System.out.println("WatchNotificationTapStateCheck PASS");
    }
}
