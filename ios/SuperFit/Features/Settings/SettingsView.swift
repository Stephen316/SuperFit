import SwiftUI

/// Gear in the top-right of every tab. Conflicting controls live top-left.
struct SettingsToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .topBarTrailing) { SettingsGear() }
            .withoutGlassBackground()
        }
    }
}

extension View {
    func settingsToolbar() -> some View { modifier(SettingsToolbarModifier()) }
}

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppAppearance.storageKey) private var appearanceRaw = AppAppearance.dark.rawValue
    @AppStorage(UnitSystem.storageKey) private var unitsRaw = UnitSystem.metric.rawValue
    @AppStorage(FoodRegionSetting.storageKey) private var foodRegionRaw = FoodRegionSetting.automatic

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background

                ScrollView {
                    VStack(spacing: 14) {
                        fitnessSection
                        dataSection
                        preferencesSection
                        aboutSection
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .themedChrome()
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .themedToolbarButton()
                }
                .withoutGlassBackground()
            }
        }
    }

    private var fitnessSection: some View {
        SettingsSection(title: "Your fitness") {
            ThemeCard(padding: 0, radius: Theme.cardRadiusCompact) {
                VStack(spacing: 0) {
                    NavigationLink {
                        ProfileView()
                    } label: {
                        SettingsNavigationRow(
                            icon: "person.text.rectangle",
                            title: "Profile",
                            subtitle: "Goals, body details and activity"
                        )
                    }

                    SettingsDivider()

                    NavigationLink {
                        HistoryView()
                    } label: {
                        SettingsNavigationRow(
                            icon: "chart.xyaxis.line",
                            title: "Trends",
                            subtitle: "Charts and training history"
                        )
                    }
                }
            }
        }
    }

    private var dataSection: some View {
        SettingsSection(title: "Data & connections") {
            ThemeCard(padding: 0, radius: Theme.cardRadiusCompact) {
                VStack(spacing: 0) {
                    NavigationLink {
                        AccountView()
                    } label: {
                        SettingsNavigationRow(
                            icon: "person.crop.circle",
                            title: "Account & data",
                            subtitle: "Storage, backups and data controls"
                        )
                    }

                    SettingsDivider()

                    NavigationLink {
                        ConnectedServicesView()
                    } label: {
                        SettingsNavigationRow(
                            icon: "link",
                            title: "Connected services",
                            subtitle: "Food search and Garmin"
                        )
                    }
                }
            }
        }
    }

    private var preferencesSection: some View {
        SettingsSection(title: "Preferences") {
            ThemeCard(padding: 16, radius: Theme.cardRadiusCompact) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "circle.lefthalf.filled")
                            .foregroundStyle(Theme.gold)
                            .frame(width: 24)
                        Text("Appearance")
                            .font(Theme.font(16, .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }

                    FeatureTabControl(
                        options: AppAppearance.allCases.map { ($0.rawValue, $0.title) },
                        selection: $appearanceRaw
                    )

                    Divider()
                        .overlay(Theme.divider)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "ruler")
                                .foregroundStyle(Theme.gold)
                            Text("Measurement units")
                                .font(Theme.font(16, .semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            SettingsInfoButton(
                                title: "Measurement units",
                                message: "Metric uses kg and cm; imperial uses lb and ft/in."
                            )
                        }
                    }

                    ThemeSegmentedControl(
                        options: UnitSystem.allCases.map { ($0.rawValue, $0.rawValue.capitalized) },
                        selection: $unitsRaw
                    )

                    Divider()
                        .overlay(Theme.divider)

                    HStack(spacing: 8) {
                        Image(systemName: "globe.europe.africa")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(Theme.gold)
                            .frame(width: 24)

                        Text("Food search country")
                            .font(Theme.font(16, .semibold))
                            .foregroundStyle(Theme.textPrimary)

                        SettingsInfoButton(
                            title: "Food search country",
                            message: "Ranks products from this region first, then nearby regions, then everywhere else. Nothing is hidden; choose where you usually buy food."
                        )

                        Spacer()
                    }

                    Menu {
                        Picker("Country", selection: $foodRegionRaw) {
                            Text(FoodRegionSetting.automaticLabel())
                                .tag(FoodRegionSetting.automatic)
                            ForEach(FoodRegion.all) { region in
                                Text(region.displayName).tag(region.code)
                            }
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Text("Country")
                                .font(Theme.font(14, .medium))
                                .foregroundStyle(Theme.textSecondary)
                            Spacer(minLength: 12)
                            Text(foodRegionName)
                                .font(Theme.font(14, .semibold))
                                .foregroundStyle(Theme.gold)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(Theme.wash, in: RoundedRectangle(
                            cornerRadius: Theme.controlRadius, style: .continuous))
                        .overlay(RoundedRectangle(
                            cornerRadius: Theme.controlRadius, style: .continuous)
                            .strokeBorder(Theme.hairline, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Food search country")
                    .accessibilityValue(foodRegionName)

                    Divider()
                        .overlay(Theme.divider)

                    ReminderToggle()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            ThemeCard(padding: 0, radius: Theme.cardRadiusCompact) {
                NavigationLink {
                    PrivacyAboutView()
                } label: {
                    SettingsNavigationRow(
                        icon: "hand.raised",
                        title: "Privacy & about",
                        subtitle: "Data storage, acknowledgements and version"
                    )
                }
            }
        }
    }

    private var foodRegionName: String {
        guard foodRegionRaw != FoodRegionSetting.automatic else {
            return FoodRegionSetting.automaticLabel()
        }
        return FoodRegion.region(forCode: foodRegionRaw)?.displayName ?? "Not available"
    }
}

private struct PrivacyAboutView: View {
    private var version: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    private var build: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
    }

    var body: some View {
        ZStack {
            Theme.background

            ScrollView {
                VStack(spacing: 14) {
                    SettingsSection(title: "Your data") {
                        ThemeCard(padding: 16, radius: Theme.cardRadiusCompact) {
                            VStack(alignment: .leading, spacing: 16) {
                                AboutInformationRow(
                                    icon: "iphone",
                                    title: "On this device",
                                    detail: deviceStorageDetail
                                )

                                SettingsDivider(inset: 0)

                                AboutInformationRow(
                                    icon: "icloud",
                                    title: "iCloud",
                                    detail: iCloudDetail
                                )

                                SettingsDivider(inset: 0)

                                AboutInformationRow(
                                    icon: "externaldrive.badge.icloud",
                                    title: "Optional cloud backup",
                                    detail: "Account backup is separate from iCloud. A snapshot of supported history is uploaded only after you sign in and choose Back up this device now. It is not live sync, and you can delete the copy from Account & data."
                                )

                                SettingsDivider(inset: 0)

                                AboutInformationRow(
                                    icon: "doc.badge.arrow.up",
                                    title: "Backup files",
                                    detail: "A backup file is created only when you choose Export backup file and is saved where you select. Saved meals and standalone cardio workouts are not included."
                                )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    SettingsSection(title: "Acknowledgements") {
                        ThemeCard(padding: 16, radius: Theme.cardRadiusCompact) {
                            AboutInformationRow(
                                icon: "fork.knife",
                                title: "Food data",
                                detail: "Food search uses USDA FoodData Central and Open Food Facts. Open Food Facts data is available under the Open Database License."
                            )
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }

                    SettingsSection(title: "App") {
                        ThemeCard(padding: 16, radius: Theme.cardRadiusCompact) {
                            VStack(spacing: 12) {
                                AboutValueRow(title: "Version", value: version ?? "Not available")
                                SettingsDivider(inset: 0)
                                AboutValueRow(title: "Build", value: build ?? "Not available")
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Privacy & about")
        .navigationBarTitleDisplayMode(.inline)
        .themedChrome()
    }

    private var deviceStorageDetail: String {
        if AppSchema.isEphemeral {
            return "Storage is unavailable in this session. Changes will be lost when SuperFit closes, so export a backup before leaving."
        }
        return "SuperFit is offline-first. Your profile, logs, workouts and measurements are stored on this device."
    }

    private var iCloudDetail: String {
        if AppSchema.isEphemeral {
            return "iCloud sync is unavailable while SuperFit is using temporary session storage."
        }
        return "iCloud sync is not enabled in this build. Your data stays on this device unless you export a backup file or create an optional cloud backup."
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(Theme.font(13, .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 4)
                .accessibilityAddTraits(.isHeader)

            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsNavigationRow: View {
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .frame(width: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(Theme.font(16, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct SettingsDivider: View {
    var inset: CGFloat = 56

    var body: some View {
        Rectangle()
            .fill(Theme.divider)
            .frame(height: 1)
            .padding(.leading, inset)
            .accessibilityHidden(true)
    }
}

private struct AboutInformationRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(Theme.font(15, .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(Theme.font(13))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct AboutValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(Theme.font(15))
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Text(value)
                .font(Theme.font(15, .medium))
                .foregroundStyle(Theme.textSecondary)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct ReminderToggle: View {
    @AppStorage(ReminderSettings.enabledKey) private var enabled = false
    @State private var isUpdating = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Theme.gold)
                .frame(width: 24)
                .accessibilityHidden(true)

            Text("Daily logging reminders")
                .font(Theme.font(16, .semibold))
                .foregroundStyle(Theme.textPrimary)

            SettingsInfoButton(
                title: "Daily logging reminders",
                message: "Morning weigh-in and breakfast, lunch at 2pm, workout at 4pm and dinner at 6pm."
            )

            Spacer(minLength: 8)

            Toggle("Daily logging reminders", isOn: Binding(
                get: { enabled },
                set: update
            ))
            .labelsHidden()
            .tint(Theme.gold)
            .disabled(isUpdating)
        }
        .accessibilityElement(children: .combine)
    }

    private func update(_ newValue: Bool) {
        isUpdating = true
        Task {
            if newValue {
                enabled = await ReminderService.enable()
            } else {
                enabled = false
                await ReminderService.disable()
            }
            isUpdating = false
        }
    }
}
