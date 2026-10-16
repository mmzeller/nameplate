import Foundation
import NameplateCore

let usage = """
nameplate - show this Mac's system information

USAGE
  nameplate                    Everything, formatted for reading
  nameplate --json             Everything as JSON (for scripts and Shortcuts)
  nameplate --get KEY [...]    Just the value(s) you ask for, one per line
  nameplate --keys             Every key with its current value

OPTIONS
  -g, --get KEY     Print one value (repeatable). Example: nameplate -g ip -g serial
  -j, --json        JSON output
  -k, --keys        List keys you can use with --get (takes a second to measure CPU and traffic)
  -l, --live        Also measure CPU usage and network traffic (takes a second)
  -p, --public-ip   Also look up the public IP (asks \(PublicIP.serviceHost))
      --no-color    Plain text even in a terminal
  -v, --version     Version
  -h, --help        This help

COMMON KEYS
  computer-name  model  serial  chip  memory  os  user  uptime
  ip  mac  router  dns  ssid  interface  disk-free  public-ip
  cpu  memory-used  battery  down  up
  <interface>.ip  <interface>.mac   e.g. en0.ip
"""

func fail(_ message: String, code: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data(("nameplate: " + message + "\n").utf8))
    exit(code)
}

// MARK: Arguments

var wantJSON = false
var wantKeys = false
var wantPublicIP = false
var wantLive = false
var useColor = isatty(STDOUT_FILENO) != 0
var requested: [String] = []

let environment = ProcessInfo.processInfo.environment
if environment["NO_COLOR"] != nil || environment["TERM"] == "dumb" || environment["TERM"] == nil {
    useColor = false
}

let arguments = Array(CommandLine.arguments.dropFirst())
var index = 0
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "-j", "--json":
        wantJSON = true
    case "-k", "--keys", "--list-keys":
        wantKeys = true
    case "-p", "--public-ip":
        wantPublicIP = true
    case "-l", "--live":
        wantLive = true
    case "--no-color", "--no-colour":
        useColor = false
    case "-h", "--help", "help":
        print(usage)
        exit(0)
    case "-v", "--version":
        print("nameplate \(NameplateInfo.version)")
        exit(0)
    case "-g", "--get":
        index += 1
        guard index < arguments.count else { fail("\(argument) needs a key. Run `nameplate --keys` to see them.") }
        requested.append(arguments[index])
    default:
        if argument.hasPrefix("--get=") {
            requested.append(String(argument.dropFirst("--get=".count)))
        } else if !argument.hasPrefix("-") {
            // Allow `nameplate serial` as a shortcut for `nameplate --get serial`.
            requested.append(argument)
        } else {
            fail("unknown option \(argument). Run `nameplate --help`.")
        }
    }
    index += 1
}

// MARK: Collect

var snapshot = SystemCollector.collect()
if wantPublicIP || requested.contains(where: { $0.lowercased() == "public-ip" }) {
    snapshot.publicIP = PublicIP.fetchAndWait()
}

// CPU and traffic are rates, so they need two samples a second apart.
let rateKeys: Set<String> = ["cpu", "down", "up"]
let measureRates = wantLive || wantKeys || requested.contains(where: { rateKeys.contains($0.lowercased()) })
let sampler = LiveSampler()
let primary = snapshot.network.primaryInterface
var needs: LiveNeeds = [.memory, .battery]
if measureRates {
    needs.formUnion([.cpu, .network])
    _ = sampler.sample([.cpu, .network], primaryInterface: primary)
    Thread.sleep(forTimeInterval: 1)
}
let live = sampler.sample(needs, primaryInterface: primary)
let input = RenderInput(snapshot: snapshot, live: live)

// MARK: Output

if wantJSON {
    print(InfoFormatter.json(snapshot))
    exit(0)
}

let values = InfoFormatter.values(for: input)

if !requested.isEmpty {
    var missing = false
    for key in requested {
        if let match = values.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }) {
            print(match.value)
        } else {
            FileHandle.standardError.write(Data("nameplate: no value for '\(key)'\n".utf8))
            missing = true
        }
    }
    exit(missing ? 1 : 0)
}

let bold = useColor ? "\u{1B}[1m" : ""
let dim = useColor ? "\u{1B}[2m" : ""
let accent = useColor ? "\u{1B}[36m" : ""
let reset = useColor ? "\u{1B}[0m" : ""

if wantKeys {
    let width = values.map { $0.key.count }.max() ?? 0
    for value in values {
        print("\(bold)\(value.key.padding(toLength: width, withPad: " ", startingAt: 0))\(reset)  \(value.value)")
    }
    exit(0)
}

var layout = Layout.everything
layout.entries.removeAll { entry in
    (!measureRates && (entry.item == .cpuUsage || entry.item == .networkSpeed))
        || (!wantPublicIP && entry.item == .publicIP)
}
let lines = InfoFormatter.lines(layout: layout, input: input, settings: .everything)
let labelWidth = lines.filter { $0.kind == .row }.map { $0.label.count }.max() ?? 0
var insideInterface = false
for line in lines {
    switch line.kind {
    case .section:
        if line.id > 0 { print("") }
        print("\(bold)\(accent)\(line.value.uppercased())\(reset)")
        insideInterface = false
    case .subheader:
        print("\(bold)\(line.value)\(reset)")
        insideInterface = true
    case .spacer:
        print("")
        insideInterface = false
    case .row:
        let indent = insideInterface ? "  " : ""
        let width = max(0, labelWidth - indent.count)
        let label = line.label.padding(toLength: width, withPad: " ", startingAt: 0)
        print("\(indent)\(dim)\(label)\(reset)  \(line.value)")
    }
}
