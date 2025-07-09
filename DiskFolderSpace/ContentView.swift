//
//  ContentView.swift
//  DiskFolderSpace
//
//  Created by Filippo Berardo on 09/07/25.
//

import SwiftUI
import Foundation

struct FolderInfo: Identifiable {
    let id = UUID()
    let url: URL
    let size: UInt64
}

class FolderAnalyzer: ObservableObject {
    @Published var folders: [FolderInfo] = []
    @Published var isLoading = false
    private var shouldCancel = false
    
    func analyze(url: URL) {
        isLoading = true
        shouldCancel = false
        DispatchQueue.global(qos: .userInitiated).async {
            var folders: [FolderInfo] = []
            if url.startAccessingSecurityScopedResource() {
                folders = self.getFolderSizes(at: url)
                url.stopAccessingSecurityScopedResource()
            }
            DispatchQueue.main.async {
                self.folders = folders.sorted { $0.size > $1.size }
                self.isLoading = false
            }
        }
    }
    
    func cancel() {
        shouldCancel = true
    }
    
    private func getFolderSizes(at url: URL) -> [FolderInfo] {
        let fileManager = FileManager.default
        guard let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else {
            return []
        }
        var result: [FolderInfo] = []
        for item in contents {
            if shouldCancel { break }
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: item.path, isDirectory: &isDir), isDir.boolValue {
                let size = self.folderSize(url: item)
                result.append(FolderInfo(url: item, size: size))
            }
        }
        return result
    }
    
    private func folderSize(url: URL) -> UInt64 {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [], errorHandler: nil) else {
            return 0
        }
        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            if shouldCancel { break }
            if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += UInt64(fileSize)
            }
        }
        return total
    }
}

struct PieSlice: Identifiable {
    let id = UUID()
    let startAngle: Angle
    let endAngle: Angle
    let color: Color
    let label: String
    let value: UInt64
}

struct PieChart: View {
    let slices: [PieSlice]
    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(slices) { slice in
                    Path { path in
                        let rect = geo.frame(in: .local)
                        let center = CGPoint(x: rect.midX, y: rect.midY)
                        let radius = min(rect.width, rect.height) / 2
                        path.move(to: center)
                        path.addArc(center: center, radius: radius, startAngle: slice.startAngle, endAngle: slice.endAngle, clockwise: false)
                    }
                    .fill(slice.color)
                }
            }
        }
    }
}

struct ContentView: View {
    @StateObject private var analyzer = FolderAnalyzer()
    @State private var selectedURL: URL? = nil
    @State private var showPicker = false
    
    private let colors: [Color] = [.blue, .green, .orange, .purple, .pink, .red, .yellow, .mint, .teal, .indigo]
    
    var body: some View {
        VStack {
            HStack {
                Button("Seleziona cartella da analizzare") {
                    showPicker = true
                }
                .padding()
                Button("Interrompi analisi") {
                    analyzer.cancel()
                }
                .padding()
                .disabled(!analyzer.isLoading)
            }
            if analyzer.isLoading {
                ProgressView("Analisi in corso...")
            } else if !analyzer.folders.isEmpty {
                Text("Contenuto di \(selectedURL?.lastPathComponent ?? "")")
                    .font(.headline)
                let total = analyzer.folders.map { $0.size }.reduce(0, +)
                let slices = pieSlices(folders: analyzer.folders, total: total)
                PieChart(slices: slices)
                    .frame(height: 300)
                    .padding()
                List(Array(zip(analyzer.folders, slices)), id: \.0.id) { pair in
                    let folder = pair.0
                    let slice = pair.1
                    HStack {
                        Circle()
                            .fill(slice.color)
                            .frame(width: 16, height: 16)
                        Text(folder.url.lastPathComponent)
                        Spacer()
                        Text(byteCountFormatter.string(fromByteCount: Int64(folder.size)))
                    }
                }
                .frame(height: 250)
            } else {
                Text("Nessuna cartella analizzata.")
            }
        }
        .fileImporter(isPresented: $showPicker, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    selectedURL = url
                    analyzer.analyze(url: url)
                }
            case .failure:
                break
            }
        }
    }
    
    private func pieSlices(folders: [FolderInfo], total: UInt64) -> [PieSlice] {
        var slices: [PieSlice] = []
        var start: Double = 0
        for (i, folder) in folders.prefix(10).enumerated() {
            let percent = total > 0 ? Double(folder.size) / Double(total) : 0
            let end = start + percent * 360
            let slice = PieSlice(
                startAngle: .degrees(start - 90),
                endAngle: .degrees(end - 90),
                color: colors[i % colors.count],
                label: folder.url.lastPathComponent,
                value: folder.size
            )
            slices.append(slice)
            start = end
        }
        return slices
    }
    
    private var byteCountFormatter: ByteCountFormatter {
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f
    }
}

#Preview {
    ContentView()
}
