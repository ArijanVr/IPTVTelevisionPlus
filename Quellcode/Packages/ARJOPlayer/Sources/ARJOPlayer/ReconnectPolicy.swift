import Foundation

public struct ReconnectPolicy: Equatable, Sendable {
    public var maxAttempts: Int
    public var baseDelay: TimeInterval
    public var maxDelay: TimeInterval
    /// So lange darf ein Sender puffern, bevor neu verbunden wird. `nil` schaltet die Überwachung aus.
    public var stallTimeout: TimeInterval?
    /// Erst nach so langer stabiler Wiedergabe gelten die Versuche wieder als unverbraucht. Sonst würde ein Stream, der kurz startet
    /// und gleich wieder abbricht, endlos neu geöffnet.
    public var stableAfter: TimeInterval

    /// Standard wie auf Samsung TV: höchstens 2 Wiederholungen nach 6 und 12 s. Viele IPTV-Zugänge erlauben nur eine Verbindung
    /// und geben sie erst verzögert frei; schnelle Wiederholungen scheitern dann oder führen zu einer Sperre beim Anbieter.
    public init(maxAttempts: Int = 2, baseDelay: TimeInterval = 6, maxDelay: TimeInterval = 12, stallTimeout: TimeInterval? = 20, stableAfter: TimeInterval = 30) {
        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.stallTimeout = stallTimeout
        self.stableAfter = stableAfter
    }

    /// Wartezeit vor Versuch `attempt` (ab 1), exponentiell bis `maxDelay`; `nil` = aufgeben.
    public func delay(forAttempt attempt: Int) -> TimeInterval? {
        guard attempt >= 1, attempt <= maxAttempts else { return nil }
        return min(baseDelay * pow(2, Double(attempt - 1)), maxDelay)
    }
}
