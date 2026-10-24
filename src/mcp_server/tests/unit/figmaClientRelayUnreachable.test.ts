import { describe, expect, it } from "bun:test";

class FakeWebSocket {
    static instances: FakeWebSocket[] = [];
    readyState = 0; // CONNECTING: never open, as when nothing listens on the relay port
    constructor(public url: string) {
        FakeWebSocket.instances.push(this);
    }
    addEventListener() {}
    send() {}
    close() {
        this.readyState = 3;
    }
}

async function importFreshClient(key: string) {
    (globalThis as any).WebSocket = FakeWebSocket;
    return import(`../../figma-client.js?relay-unreachable-${key}`);
}

function expectRelayUnreachable(error: any, url: string) {
    expect(error.code).toBe("RELAY_UNREACHABLE");
    // The live verifiers match on this prefix.
    expect(error.message.startsWith("Not connected to Figma")).toBe(true);
    expect(error.message).toContain(url);
    expect(error.message).toContain("npx -y --package figma-edit-mcp figma-edit-mcp-socket");
    expect(error.message).toContain("scripts/install-relay-service.sh");
    expect(error.details).toEqual({ relayUrl: url });
}

describe("figma-client: relay not reachable is a coded, actionable error", () => {
    it("joinChannel rejects with RELAY_UNREACHABLE naming the relay URL it tried", async () => {
        const client = await importFreshClient("join");
        client.setFigmaServerUrl("ws://localhost");
        client.connectToFigma(3155); // never opens
        const error = await client.joinChannel("any").then(() => null, (e: unknown) => e);
        expect(error).toBeInstanceOf(client.FigmaError);
        expectRelayUnreachable(error, "ws://localhost:3155");
    });

    it("sendCommandToFigma rejects with RELAY_UNREACHABLE and still starts a reconnect", async () => {
        const client = await importFreshClient("send");
        client.setFigmaServerUrl("ws://localhost");
        const before = FakeWebSocket.instances.length;
        const error = await client.sendCommandToFigma("join", {}, 50).then(() => null, (e: unknown) => e);
        expect(error).toBeInstanceOf(client.FigmaError);
        expectRelayUnreachable(error, "ws://localhost:3055");
        expect(FakeWebSocket.instances.length).toBe(before + 1);
    });
});
