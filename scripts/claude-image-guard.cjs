"use strict";
const { spawn } = require("child_process");
const path = require("path");
const readline = require("readline");
const NOTICE = "当前 Claude 3.7 接口的图片链路未通过验证。为避免图片导致后续对话持续报错，本次图片未送入模型，上下文已保留。请把图片内容转成文字后再发送。";

function containsImage(value) {
  if (!value || typeof value !== "object") return false;
  if (value.type === "image" || value.type === "image_url") return true;
  return Object.values(value).some(v => Array.isArray(v) ? v.some(containsImage) : containsImage(v));
}

function toolDecision(input) {
  const file = input.tool_input?.file_path || input.tool_input?.path || "";
  if (input.tool_name === "Read" && /\.(png|jpe?g|gif|webp|bmp|tiff?|heic|avif)$/i.test(file)) {
    return { hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: NOTICE } };
  }
  return {};
}

function createBridge({ args, launch, output, errorOutput }) {
  let child = null;
  let sessionId = args[args.indexOf("--resume") + 1];
  if (!args.includes("--resume")) sessionId = "";
  function start() {
    if (child) return child;
    child = launch(args);
    const lines = readline.createInterface({ input: child.stdout });
    lines.on("line", line => {
      try { const event = JSON.parse(line); if (event.session_id) sessionId = event.session_id; } catch {}
      output(line + "\n");
    });
    child.stderr.on("data", data => errorOutput(data));
    return child;
  }
  return {
    accept(line) {
      let message;
      try { message = JSON.parse(line); } catch { throw new Error("Invalid Claude bridge input JSON"); }
      if (message.type === "user" && containsImage(message.message?.content)) {
        // No image, placeholder user turn, or error body enters Claude's transcript.
        output(JSON.stringify({ type: "result", subtype: "success", is_error: false, result: NOTICE, session_id: sessionId }) + "\n");
        return;
      }
      start().stdin.write(line + "\n");
    },
    close() { if (child) child.stdin.end(); },
    stop() { if (child) child.kill(); }
  };
}

async function main() {
  const args = process.argv.slice(2);
  if (args[0] === "--tool-check") {
    let input = "";
    for await (const chunk of process.stdin) input += chunk;
    console.log(JSON.stringify(toolDecision(JSON.parse(input))));
    return;
  }
  const binary = path.join(process.env.APPDATA, "npm/node_modules/@anthropic-ai/claude-code/bin/claude.exe");
  if (!args.includes("stream-json")) {
    const child = spawn(binary, args, { stdio: "inherit", windowsHide: true });
    child.on("error", () => { process.stderr.write("Claude executable could not start\n"); process.exitCode = 1; });
    child.on("exit", code => { process.exitCode = code ?? 1; });
    return;
  }
  const bridge = createBridge({
    args,
    launch(actualArgs) {
      const settings = path.join(__dirname, "image-guard-settings.json");
      const child = spawn(binary, [...actualArgs, "--settings", settings], { stdio: ["pipe", "pipe", "pipe"], windowsHide: true });
      child.on("error", () => { process.stderr.write("Claude executable could not start\n"); process.exitCode = 1; process.stdin.destroy(); });
      child.on("exit", code => { process.exitCode = code ?? 1; process.stdin.destroy(); });
      return child;
    },
    output: text => process.stdout.write(text),
    errorOutput: text => process.stderr.write(text)
  });
  for (const signal of ["SIGINT", "SIGTERM"]) process.on(signal, () => { bridge.stop(); process.exit(0); });
  const input = readline.createInterface({ input: process.stdin });
  input.on("line", line => { try { bridge.accept(line); } catch (e) { process.stderr.write(e.message + "\n"); bridge.stop(); process.exitCode = 1; input.close(); } });
  input.on("close", () => bridge.close());
}

module.exports = { containsImage, toolDecision, createBridge, NOTICE };
if (require.main === module) main().catch(() => { process.stderr.write("Claude image guard failed\n"); process.exitCode = 1; });
