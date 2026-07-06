import Foundation
import Realtime

/// Subscribes to Postgres change notifications on the tables shared-project
/// collaboration touches (tasks/events/notes) and calls `onChange` whenever
/// ANY row in ANY subscribed project changes — deliberately coarse-grained.
/// We refetch-on-signal rather than hand-merging individual row deltas: the
/// existing `AppState`/`AtlasDB` load path already knows how to load a
/// consistent snapshot, and reimplementing that as an incremental patch
/// pipeline is speculative complexity this phase doesn't need.
public final class RealtimeSyncService {
    private let client: RealtimeClientV2
    private var channels: [RealtimeChannelV2] = []

    public init(supabaseURL: URL, anonKey: String) {
        self.client = RealtimeClientV2(
            url: supabaseURL.appendingPathComponent("realtime/v1"),
            options: RealtimeClientOptions(headers: ["apikey": anonKey])
        )
    }

    /// Opens one channel per shared project id and calls `onChange` (coalesced
    /// to at most one call per event, no debouncing beyond that) whenever a
    /// task/event/note row changes in that project. Call `unsubscribeAll()`
    /// first if resubscribing with a different project id list.
    public func subscribe(projectIds: [UUID], onChange: @escaping () -> Void) async {
        await client.connect()
        for projectId in projectIds {
            let channel = client.channel("project:\(projectId.uuidString)")
            for table in ["tasks", "events", "notes"] {
                _ = channel.onPostgresChange(
                    AnyAction.self,
                    schema: "public",
                    table: table,
                    filter: "project_id=eq.\(projectId.uuidString)"
                ) { _ in
                    onChange()
                }
            }
            try? await channel.subscribeWithError()
            channels.append(channel)
        }
    }

    public func unsubscribeAll() async {
        for channel in channels {
            await channel.unsubscribe()
        }
        channels.removeAll()
        client.disconnect()
    }
}
