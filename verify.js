#!/usr/bin/env node
// Verifies patch via CDP connection to OpenCode (must be running with --remote-debugging-port=9222)
const http = require('http');
const net = require('net');

async function cdpRequest(wsUrl, expression) {
  return new Promise((resolve, reject) => {
    const url = new URL(wsUrl);
    const socket = net.connect(url.port, url.hostname);
    const key = Buffer.from(Math.random().toString(36)).toString('base64');
    const headers = [
      `GET ${url.pathname} HTTP/1.1`,
      `Host: ${url.host}`,
      `Upgrade: websocket`,
      `Connection: Upgrade`,
      `Sec-WebSocket-Key: ${key}`,
      `Sec-WebSocket-Version: 13`,
      '', ''
    ].join('\r\n');

    let upgraded = false;
    let buf = Buffer.alloc(0);

    socket.on('data', chunk => {
      buf = Buffer.concat([buf, chunk]);
      if (!upgraded) {
        const header = buf.toString();
        if (header.includes('\r\n\r\n')) { upgraded = true; buf = Buffer.alloc(0); }
        return;
      }
      // Minimal WebSocket frame parser
      if (buf.length < 2) return;
      const fin = (buf[0] & 0x80) !== 0;
      const opcode = buf[0] & 0x0f;
      let len = buf[1] & 0x7f;
      let offset = 2;
      if (len === 126) { len = buf.readUInt16BE(2); offset = 4; }
      if (buf.length < offset + len) return;
      const payload = buf.slice(offset, offset + len).toString();
      try {
        const msg = JSON.parse(payload);
        if (msg.id === 1) { socket.destroy(); resolve(msg.result?.result?.value ?? msg.result); }
      } catch {}
    });

    socket.on('connect', () => socket.write(headers));
    socket.on('error', reject);

    socket.once('data', () => {
      // Send Runtime.evaluate after upgrade
      setTimeout(() => {
        const body = JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression } });
        const frame = Buffer.alloc(body.length + 6);
        frame[0] = 0x81; // FIN + text
        frame[1] = 0x80 | body.length; // masked, length (assumes <126)
        const mask = [0, 0, 0, 0]; // zero mask
        frame.writeUInt32BE(0, 2);
        Buffer.from(body).copy(frame, 6);
        socket.write(frame);
      }, 200);
    });
  });
}

async function main() {
  // Get WS URL
  const pages = await new Promise((res, rej) => {
    http.get('http://localhost:9222/json/list', r => {
      let d = ''; r.on('data', c => d += c); r.on('end', () => res(JSON.parse(d)));
    }).on('error', rej);
  });
  const page = pages.find(p => p.title === 'OpenCode') || pages[0];
  if (!page) { console.error('OpenCode not running on port 9222'); process.exit(1); }
  console.log('Connected to:', page.title);

  const result = await cdpRequest(page.webSocketDebuggerUrl, `
    (() => {
      // Read the compiled chunk from the loaded modules via require cache
      try {
        const mods = Object.keys(require.cache || {});
        const chunk = mods.find(m => m.includes('node-C8DkvgUn'));
        if (!chunk) return 'chunk not in require.cache (normal for asar)';
        const src = require('fs').readFileSync(chunk, 'utf8');
        return JSON.stringify({
          tool_input_delta_guarded: src.includes('case "tool-input-delta":\\n            {\\n              if (ctx.assistantMessage.summary) return;'),
          tool_input_end_guarded: src.includes('case "tool-input-end": {\\n              if (ctx.assistantMessage.summary) return;'),
          throw_remains: src.includes('Tool call not allowed while generating summary'),
        });
      } catch(e) { return e.message; }
    })()
  `);
  console.log('Patch verification:', result);
}

main().catch(e => { console.error(e.message); process.exit(1); });
