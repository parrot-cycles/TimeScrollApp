import Foundation

// Entry logic for the MCP helper. This is invoked from the target's main.swift.
struct MCPMain {
	static func start() {
		setbuf(stdout, nil) // flush JSON lines promptly
		fputs("[scrollback-mcp] starting\n", stderr)
		MCPFileLogger.log("helper starting")
		let server = MCPServer()
		Task.detached(priority: .userInitiated) {
			server.run()
		}
		// Keep main thread free for MainActor work (SearchService, etc.)
		dispatchMain()
	}
}
