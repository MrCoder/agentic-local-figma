import { describe, it, expect } from "bun:test";
import { spawn } from "child_process";
import { resolve } from "path";
import { SERVER_VERSION } from "../../shared/version.js";

describe("relay startup log", () => {
    it("names the package version, PID and ISO start time so ownership is visible", async () => {
        const port = 3098;
        const socketPath = resolve(import.meta.dir, "../../socket.ts");
        const socket = spawn(process.execPath, [socketPath, "--port", String(port)], {
            stdio: ["ignore", "pipe", "pipe"],
        });
        let out = "";
        try {
            await new Promise<void>((res, rej) => {
                const t = setTimeout(() => rej(new Error(`socket did not start; output: ${out}`)), 5000);
                socket.stdout.on("data", (d: Buffer) => {
                    out += d.toString();
                    if (out.includes("\n")) { clearTimeout(t); res(); }
                });
            });
            const line = out.split("\n")[0];
            // The "WebSocket server running on host:port" prefix is what
            // existing smoke checks wait for; the suffix is the ownership info.
            const match = line.match(
                /^WebSocket server running on (\S+):3098 \(figma-edit-mcp-socket v(\S+), pid (\d+), started (\S+)\)$/,
            );
            expect(match, `unexpected startup line: ${line}`).not.toBeNull();
            expect(match![2]).toBe(SERVER_VERSION);
            expect(Number(match![3])).toBe(socket.pid!);
            expect(new Date(match![4]).toISOString()).toBe(match![4]);
        } finally {
            socket.kill("SIGKILL");
        }
    }, 15000);
});
