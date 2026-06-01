import SwiftUI

struct SubmitAllPreviewView: View {
    let items: [DiffLine]
    @Binding var isPresented: Bool
    let onSubmit: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Submit \(items.count) Unrecognized Change\(items.count == 1 ? "" : "s")")
                .font(.headline)
            Text("This data will be sent to the developer to help identify similar changes in the future. Submitted data is transmitted securely and stored privately. No personally identifying information is collected or stored.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(spacing: 6) {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.rawLine)
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                HStack(spacing: 6) {
                                    Text(item.beforeValue.isEmpty ? "(none)" : formatValue(item.beforeValue, key: item.key))
                                        .foregroundStyle(.orange)
                                    Text("→").foregroundStyle(.secondary)
                                    Text(item.afterValue.isEmpty ? "(none)" : formatValue(item.afterValue, key: item.key))
                                        .foregroundStyle(.blue)
                                }
                                .font(.system(.caption, design: .monospaced))
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.secondary.opacity(0.08))
                        .cornerRadius(8)
                    }
                }
            }
            .frame(maxHeight: 300)

            HStack {
                Button("Cancel") { isPresented = false }
                Spacer()
                Button("Submit All") {
                    onSubmit()
                    isPresented = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(28)
        .frame(width: 480)
    }
}
