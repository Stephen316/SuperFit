import Testing
@testable import SuperFit

struct SupabaseAccountTests {
    /// Pins the opt-in until the next major Supabase SDK makes it the default;
    /// otherwise constructing an auth observer logs a migration warning and
    /// retains the legacy refresh-before-initial-emission behavior.
    @Test func clientOptsIntoLocalInitialSessionEmission() {
        #expect(SupabaseConfig.clientOptions.auth.emitLocalSessionAsInitialSession)
    }
}
