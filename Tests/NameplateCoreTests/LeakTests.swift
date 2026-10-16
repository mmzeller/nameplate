import XCTest
import Darwin
import NameplateCore

/// Checks that the parts Nameplate runs over and over don't leak memory, Mach ports
/// or file handles, and that your commands can't hang it. Lines starting with RESULT
/// are collected into the build report.
final class LeakTests: XCTestCase {

    // MARK: Commands

    func testCommandRunnerClosesFileHandles() {
        _ = CommandRunner.run("echo warm-up")
        let before = openFileCount()
        for i in 0..<300 {
            XCTAssertEqual(CommandRunner.run("echo \(i)"), "\(i)")
        }
        let after = openFileCount()
        print("RESULT commands: 300 runs, open files \(before) -> \(after)")
        XCTAssertLessThanOrEqual(after - before, 2, "open files went from \(before) to \(after)")
    }

    func testCommandRunnerTimesOut() {
        let start = Date()
        let output = CommandRunner.run("sleep 30", timeout: 1)
        let elapsed = Date().timeIntervalSince(start)
        print("RESULT timeout: stopped after \(String(format: "%.1f", elapsed)) s, said \"\(output)\"")
        XCTAssertLessThan(elapsed, 5)
        XCTAssertTrue(output.contains("Timed out"), output)
    }

    func testCommandRunnerDoesNotWaitForBackgroundPrograms() {
        let start = Date()
        let output = CommandRunner.run("sleep 20 & echo started", timeout: 10)
        let elapsed = Date().timeIntervalSince(start)
        print("RESULT background program: returned after \(String(format: "%.1f", elapsed)) s")
        XCTAssertEqual(output, "started")
        XCTAssertLessThan(elapsed, 3)
    }

    func testCommandRunnerKeepsBigOutputBounded() {
        let output = CommandRunner.run("yes nameplate | head -c 500000")
        XCTAssertLessThanOrEqual(output.utf8.count, 32_768)
        XCTAssertTrue(output.hasPrefix("nameplate"))
    }

    // MARK: Sampling and formatting

    func testRepeatedSamplingDoesNotLeak() {
        let sampler = LiveSampler()
        var snapshot = SystemCollector.collect()
        let layout = Layout.everything
        // Warm up caches first, so one-time allocations don't count as growth.
        for _ in 0..<50 {
            autoreleasepool {
                _ = sampler.sample(.sampled, primaryInterface: snapshot.network.primaryInterface)
                snapshot = SystemCollector.collect(reusingHardwareFrom: snapshot)
                _ = InfoFormatter.lines(layout: layout, input: RenderInput(snapshot: snapshot), settings: .everything)
            }
        }
        let memoryBefore = footprint()
        let portsBefore = portCount()
        let filesBefore = openFileCount()

        for i in 0..<3000 {
            autoreleasepool {
                let live = sampler.sample(.sampled, primaryInterface: snapshot.network.primaryInterface)
                if i % 10 == 0 {
                    snapshot = SystemCollector.collect(reusingHardwareFrom: snapshot)
                }
                let input = RenderInput(snapshot: snapshot, live: live)
                _ = InfoFormatter.lines(layout: layout, input: input, settings: .everything)
                _ = InfoFormatter.render(template: "{cpu} {memory-used} {down} {up} {time}", values: InfoFormatter.valueDictionary(input))
            }
        }

        let memoryAfter = footprint()
        let portsAfter = portCount()
        let filesAfter = openFileCount()
        let growth = Int64(memoryAfter) - Int64(memoryBefore)
        print("RESULT sampling: 3000 live samples, 300 full refreshes, 3000 redraws; memory \(mb(memoryBefore)) -> \(mb(memoryAfter)), Mach ports \(portsBefore) -> \(portsAfter), open files \(filesBefore) -> \(filesAfter)")
        XCTAssertLessThan(growth, 8 * 1_048_576, "memory grew by \(growth) bytes")
        XCTAssertLessThanOrEqual(portsAfter - portsBefore, 5)
        XCTAssertLessThanOrEqual(filesAfter - filesBefore, 2)
    }

    func testFullHardwareReadDoesNotLeak() {
        for _ in 0..<10 { autoreleasepool { _ = SystemCollector.collect() } }
        let memoryBefore = footprint()
        let portsBefore = portCount()
        for _ in 0..<150 { autoreleasepool { _ = SystemCollector.collect() } }
        let memoryAfter = footprint()
        let portsAfter = portCount()
        print("RESULT full read: 150 complete reads (hardware, graphics, disks, network); memory \(mb(memoryBefore)) -> \(mb(memoryAfter)), Mach ports \(portsBefore) -> \(portsAfter)")
        XCTAssertLessThan(Int64(memoryAfter) - Int64(memoryBefore), 8 * 1_048_576)
        XCTAssertLessThanOrEqual(portsAfter - portsBefore, 5)
    }

    // MARK: Safety of saved settings and placeholders

    func testDamagedLayoutIsIgnoredSafely() throws {
        let damaged = #"{"entries":[{"kind":"item","item":"somethingFromTheFuture"},{"kind":"bogus"},{"kind":"item","item":"serialNumber","enabled":false}],"interfaceDetails":"nope"}"#
        var layout = try JSONDecoder().decode(Layout.self, from: Data(damaged.utf8))
        layout.addMissingItems()
        XCTAssertFalse(layout.entries.contains { $0.kind == .item && $0.item == nil })
        XCTAssertEqual(layout.entries.filter { $0.item == .serialNumber }.count, 1)
        XCTAssertEqual(layout.interfaceDetails.count, Layout.detailItems.count)
    }

    func testPlaceholdersAreJustText() {
        let values = ["ip": "10.0.0.5", "ssid": "$(rm -rf ~) `whoami`"]
        XCTAssertEqual(InfoFormatter.render(template: "IP {ip} on {ssid}", values: values), "IP 10.0.0.5 on $(rm -rf ~) `whoami`")
        XCTAssertEqual(InfoFormatter.render(template: "{typo}", values: values), "{typo}")
        XCTAssertEqual(InfoFormatter.render(template: "{cpu}", values: values), "")
        XCTAssertEqual(InfoFormatter.render(template: "unclosed {ip", values: values), "unclosed {ip")
    }

    // MARK: Measuring

    private func footprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let capacity = Int(count)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: capacity) { raw in
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), raw, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    private func portCount() -> Int {
        var names: mach_port_name_array_t?
        var namesCount: mach_msg_type_number_t = 0
        var types: mach_port_type_array_t?
        var typesCount: mach_msg_type_number_t = 0
        guard mach_port_names(mach_task_self_, &names, &namesCount, &types, &typesCount) == KERN_SUCCESS else { return -1 }
        if let names {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: names),
                          vm_size_t(namesCount) * vm_size_t(MemoryLayout<mach_port_name_t>.size))
        }
        if let types {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: types),
                          vm_size_t(typesCount) * vm_size_t(MemoryLayout<mach_port_type_t>.size))
        }
        return Int(namesCount)
    }

    private func openFileCount() -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: "/dev/fd").count) ?? -1
    }

    private func mb(_ bytes: UInt64) -> String {
        String(format: "%.1f MB", Double(bytes) / 1_048_576)
    }
}
