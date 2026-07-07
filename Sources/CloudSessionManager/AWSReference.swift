import SwiftUI

/// Static AWS reference data (regions, output formats) plus the reusable
/// form controls that present them as dropdowns.
enum AWSReference {
    struct Region: Identifiable, Hashable {
        let code: String
        let name: String
        var id: String { code }
        var menuLabel: String { "\(code) — \(name)" }
    }

    /// Commercial AWS regions. GovCloud/China partitions are intentionally
    /// omitted; a config using one still round-trips via the "custom" fallback.
    static let regions: [Region] = [
        .init(code: "us-east-1", name: "US East (N. Virginia)"),
        .init(code: "us-east-2", name: "US East (Ohio)"),
        .init(code: "us-west-1", name: "US West (N. California)"),
        .init(code: "us-west-2", name: "US West (Oregon)"),
        .init(code: "ca-central-1", name: "Canada (Central)"),
        .init(code: "ca-west-1", name: "Canada West (Calgary)"),
        .init(code: "sa-east-1", name: "South America (São Paulo)"),
        .init(code: "eu-west-1", name: "Europe (Ireland)"),
        .init(code: "eu-west-2", name: "Europe (London)"),
        .init(code: "eu-west-3", name: "Europe (Paris)"),
        .init(code: "eu-central-1", name: "Europe (Frankfurt)"),
        .init(code: "eu-central-2", name: "Europe (Zurich)"),
        .init(code: "eu-north-1", name: "Europe (Stockholm)"),
        .init(code: "eu-south-1", name: "Europe (Milan)"),
        .init(code: "eu-south-2", name: "Europe (Spain)"),
        .init(code: "af-south-1", name: "Africa (Cape Town)"),
        .init(code: "me-central-1", name: "Middle East (UAE)"),
        .init(code: "me-south-1", name: "Middle East (Bahrain)"),
        .init(code: "il-central-1", name: "Israel (Tel Aviv)"),
        .init(code: "ap-south-1", name: "Asia Pacific (Mumbai)"),
        .init(code: "ap-south-2", name: "Asia Pacific (Hyderabad)"),
        .init(code: "ap-northeast-1", name: "Asia Pacific (Tokyo)"),
        .init(code: "ap-northeast-2", name: "Asia Pacific (Seoul)"),
        .init(code: "ap-northeast-3", name: "Asia Pacific (Osaka)"),
        .init(code: "ap-southeast-1", name: "Asia Pacific (Singapore)"),
        .init(code: "ap-southeast-2", name: "Asia Pacific (Sydney)"),
        .init(code: "ap-southeast-3", name: "Asia Pacific (Jakarta)"),
        .init(code: "ap-southeast-4", name: "Asia Pacific (Melbourne)"),
        .init(code: "ap-east-1", name: "Asia Pacific (Hong Kong)"),
    ]

    static func regionName(for code: String) -> String? {
        regions.first { $0.code == code }?.name
    }

    /// `aws configure` output formats, in the CLI's documented order.
    static let outputFormats = ["json", "yaml", "yaml-stream", "text", "table"]
}

/// A region dropdown. Any region string the config already holds that isn't in
/// the known list is surfaced as a "(custom)" entry so nothing is silently lost.
struct RegionPicker: View {
    let title: String
    @Binding var selection: String
    /// When true, offers a leading option that stores an empty string
    /// (e.g. "inherit from the SSO session").
    var emptyOption: String?

    var body: some View {
        Picker(title, selection: $selection) {
            if let emptyOption {
                Text(emptyOption).tag("")
            }
            if !selection.isEmpty,
               !AWSReference.regions.contains(where: { $0.code == selection }) {
                Text("\(selection) (custom)").tag(selection)
            }
            ForEach(AWSReference.regions) { region in
                Text(region.menuLabel).tag(region.code)
            }
        }
        .pickerStyle(.menu)
    }
}

/// An output-format dropdown. An empty selection means "unset" — the CLI then
/// falls back to its own default (json).
struct OutputFormatPicker: View {
    @Binding var selection: String

    var body: some View {
        Picker("Output format", selection: $selection) {
            Text("Default (json)").tag("")
            if !selection.isEmpty, !AWSReference.outputFormats.contains(selection) {
                Text("\(selection) (custom)").tag(selection)
            }
            ForEach(AWSReference.outputFormats, id: \.self) { format in
                Text(format).tag(format)
            }
        }
        .pickerStyle(.menu)
    }
}
