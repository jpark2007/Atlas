// CARRYOVER — from old Atlas prototype. Depends on old `DS` design system + Bucket/AtlasProject
// and several old sub-views (FocusBentoPicker, FocusHistoryView, FocusBackgroundPaths, etc.).
// The active-session timer UI: 144pt serif display + Capsule() pill button + Space = break.
import SwiftUI
import SwiftData

struct FocusView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Bucket.sortOrder) private var allBuckets: [Bucket]
    let vm: FocusViewModel
    @State private var showReflectionSheet = false
    @State private var pendingStartBucket: Bucket?
    @State private var showOverflowSheet = false

    private var overflowBuckets: [Bucket] {
        allBuckets.filter { b in
            guard let slot = b.slotIndex else { return true }
            return slot < 0 || slot > 2
        }
    }
    @State private var showAddBucketSheet = false
    @State private var newBucketName = ""
    @AppStorage("sidebarCollapsed") private var sidebarCollapsed: Bool = false
    @State private var sidebarCollapsedBeforeFocus: Bool = false

    var body: some View {
        ZStack {
            if vm.isRunning {
                activeSession
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.92)).animation(.easeInOut(duration: 0.4)),
                        removal: .opacity.animation(.easeInOut(duration: 0.3))
                    ))
            } else {
                picker
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.98)).animation(.easeInOut(duration: 0.4)),
                        removal: .opacity.animation(.easeInOut(duration: 0.3))
                    ))
            }
        }
        .background(DS.Colors.bgPrimary)
        .sheet(isPresented: $showReflectionSheet, onDismiss: {
            sidebarCollapsed = sidebarCollapsedBeforeFocus
        }) {
            FocusReflectionSheet(vm: vm)
        }
        .onChange(of: vm.isRunning) { _, running in
            if running {
                sidebarCollapsedBeforeFocus = sidebarCollapsed
                sidebarCollapsed = true
            }
        }
        .sheet(item: $pendingStartBucket) { bucket in
            FocusStartSheet(bucket: bucket) { project, intention in
                vm.startSession(project: project, intention: intention, context: context)
            }
        }
        .sheet(isPresented: $showOverflowSheet) {
            FocusBucketListSheet(buckets: overflowBuckets) { bucket in
                pendingStartBucket = bucket
            }
        }
        .sheet(isPresented: $showAddBucketSheet) {
            addBucketSheet
        }
    }

    // MARK: - Active session (with pill timer)

    private var activeSession: some View {
        ZStack {
            FocusBackgroundPaths()
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()

                Text("— \(projectLabel) —")
                    .font(DS.Typography.serifLabelKerned)
                    .textCase(.uppercase)
                    .kerning(3)
                    .foregroundColor(DS.Colors.textMuted)

                if let intention = vm.currentSession?.intention, !intention.isEmpty {
                    Text(intention)
                        .font(DS.Typography.serifSubtitle)
                        .foregroundColor(DS.Colors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 48)
                }

                if vm.isOnBreak {
                    Text("Break · \(vm.breakElapsedFormatted)")
                        .font(DS.Typography.serifSubtitle)
                        .foregroundColor(DS.Colors.warmAccent)
                        .monospacedDigit()
                        .transition(.opacity)
                }

                // PILL TIMER — 144pt serif display, monospaced digits
                Text(vm.elapsedFormatted)
                    .font(DS.Typography.timerHero)
                    .monospacedDigit()
                    .foregroundColor(vm.isOnBreak ? DS.Colors.textGhost : DS.Colors.textPrimary)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if vm.isOnBreak { vm.endBreak() } else { vm.startBreak() }
                    }
                    .help(vm.isOnBreak ? "Click to resume · Space" : "Click to take a break · Space")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityLabel(vm.isOnBreak
                        ? "On break, \(vm.breakElapsedFormatted)"
                        : "Focus timer, \(vm.elapsedFormatted)")
                    .accessibilityHint(vm.isOnBreak
                        ? "Double tap to resume focus. Space also works."
                        : "Double tap to start a break. Space also works.")

                // PILL BUTTON — Capsule shape with icon and text
                Button {
                    vm.requestEndSession()
                    showReflectionSheet = true
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 10))
                        Text("End Session")
                            .font(DS.Typography.body)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(DS.Colors.bgPrimary)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(DS.Colors.accentAction)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(vm.isOnBreak
                    ? "Ends session. Current break will be saved."
                    : "Ends session and opens reflection")

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.25), value: vm.isOnBreak)
        }
        .background(
            // Invisible button that captures Space to toggle break.
            Button("") {
                if vm.isOnBreak { vm.endBreak() } else { vm.startBreak() }
            }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .disabled(showReflectionSheet)
        )
    }

    private var projectLabel: String {
        (vm.selectedProject?.name ?? "Focus").uppercased()
    }

    // MARK: - Picker (session start screen)

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Focus Mode")
                        .font(.system(size: 44, weight: .medium, design: .serif))
                        .foregroundColor(DS.Colors.textPrimary)
                    Text("Select a bucket to narrow your focus")
                        .font(DS.Typography.serifCaption)
                        .foregroundColor(DS.Colors.textMuted)
                }
                .padding(.horizontal, DS.Spacing.xxxl)
                .padding(.top, DS.Spacing.xxl)
                .padding(.bottom, DS.Spacing.xl)

                FocusBentoPicker(
                    onBucketTapped: { bucket in pendingStartBucket = bucket },
                    onOverflowTapped: { _ in showOverflowSheet = true },
                    onAddBucketTapped: {
                        newBucketName = ""
                        showAddBucketSheet = true
                    }
                )

                FocusHistoryView()
                    .padding(.top, DS.Spacing.xxl)
            }
        }
    }

    // NOTE: addBucketSheet omitted in carryover — rebuild against the new data model.
    private var addBucketSheet: some View { EmptyView() }
}
