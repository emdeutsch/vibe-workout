import SwiftUI

enum ActivitySegment: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case projects = "Projects"
    case sessions = "Sessions"

    var id: String { rawValue }
}

struct ActivityView: View {
    @State private var selectedSegment: ActivitySegment = .overview

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control
                Picker("View", selection: $selectedSegment) {
                    ForEach(ActivitySegment.allCases) { segment in
                        Text(segment.rawValue).tag(segment)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Spacing.md)
                .padding(.vertical, Spacing.sm)

                // Content
                Group {
                    switch selectedSegment {
                    case .overview:
                        OverviewView()
                    case .projects:
                        ProjectsListView()
                    case .sessions:
                        SessionsListView()
                    }
                }
            }
            .navigationTitle("Activity")
        }
    }
}

#Preview {
    ActivityView()
        .environmentObject(APIService.shared)
}
