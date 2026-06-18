# iOS sideload packaging

These scripts build a Flutter iOS app without Apple distribution signing, then package the resulting `.app` into a sideload IPA.

The generated IPA is intended for tools such as AltStore, SideStore, or similar self-signing installers.
