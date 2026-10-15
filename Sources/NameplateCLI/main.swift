import Foundation
import NameplateCore

let usage = """
nameplate — show this Mac's system information

USAGE
  nameplate                    Everything, formatted for reading
  nameplate --json             Everything as JSON (for scripts and Shortcuts)
  nameplate --get KEY [...]    Just the value(s) you ask for, one per line
  nameplate --keys             Every key with its current value

OPTIONS
  -g, --get KEY     Print one value (repeatable). Example: nameplate -g ip -g serial
  -j, --json        JSON output
  -k, --keys        List keys you can use with --get
  -p, --public-ip   Also look up the public IP (asks \(PublicIP.serviceHost))
      --no-color    Plain text even in a terminal
  -v, --version     Version
  -h, --help        This help

COMMON KEYS
  computer-name  model  serial  chip  memory  os  user  uptime
  ip  mac  router  dns  ssid  interface  disk-free  public-ip
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
if wantPublicIP || requested.contains("public-ip") {
    snapshot.publicIP = PublicIP.fetchAndWait()
}

// MARK: Output

if wantJSON {
    print(InfoFormatter.json(snapshot))
    exit(0)
}

let values = InfoFormatter.values(for: snapshot)

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
    let width = values.map(\.key.count).max() ?? 0
    for value in values {
        print("\(bold)\(value.key.padding(toLength: width, withPad: " ", startingAt: 0))\(reset)  \(value.value)")
    }
    exit(0)
}

var options = DisplayOptions.everything
if !(wantPublicIP) { options.enabled.remove(.publicIP) }
let lines = InfoFormatter.lines(for: snapshot, options: options)
let labelWidth = lines.filter { $0.kind == .row }.map(\.label.count).max() ?? 0
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
