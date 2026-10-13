package com.example.south_plus_rewrite;

public final class IncomingLinkStateCheck {
    public static void main(String[] args) {
        String cold = "https://south-plus.net/read.php?tid-701.html#fixture%2Danchor";
        String warm = "https://blue-plus.net/search.php?keyword=fixture%2Dterm";
        IncomingLinkState state = new IncomingLinkState(0, false);
        state.restore(cold);
        assert state.pending() != null : "cold VIEW must be retained";
        assert state.pending().get("url").equals(cold);
        assert state.sequence() == 1;
        state.receive(warm);
        state.acknowledge(1);
        assert !state.consumed() : "old acknowledgement cannot consume a newer link";
        assert state.pending().get("url").equals(warm);
        IncomingLinkState recreated = new IncomingLinkState(state.sequence(), state.consumed());
        recreated.restore(warm);
        assert recreated.sequence() == 2;
        assert recreated.pending().get("url").equals(warm);
        recreated.acknowledge(2);
        assert recreated.consumed() && recreated.pending() == null;
        IncomingLinkState consumed = new IncomingLinkState(recreated.sequence(), recreated.consumed());
        consumed.restore(warm);
        assert consumed.pending() == null : "consumed Activity intent must not replay";
        consumed.receive(warm);
        assert consumed.sequence() == 3 && consumed.pending().get("url").equals(warm);
        for (String safe : new String[] {
            "https://BBS.SOUTH-PLUS.NET./faq.php", "http://www.imoutolove.me:80/read.php?tid-701.html",
            "https://south-plus.net:443/read.php?tid-701.html"
        }) {
            consumed.receive(safe);
            assert consumed.pending().get("url").equals(safe) : "owned unsupported page stays available for Dart copy-only";
        }
        for (String unsafe : new String[] {
            "https://south-plus.net.evil.invalid/read.php", "https://evil-south-plus.net/read.php",
            "https://user:password@south-plus.net/read.php", "https://@south-plus.net/read.php",
            "https://south-plus.net:444/read.php", "javascript:alert(1)", "/read.php?tid-701.html",
            "https://south-plus.net/%broken", "https://south-plus.net/\nfixture", "x".repeat(8193)
        }) {
            consumed.receive(unsafe);
            assert consumed.pending().get("url").equals("") : "unsafe URL must never cross the channel";
        }
        System.out.println("IncomingLinkStateCheck PASS");
    }
}
