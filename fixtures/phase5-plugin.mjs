const mode = process.argv[2] ?? "success";

if (mode === "slow") {
  setTimeout(() => process.stdout.write('{"ok":true,"result":"late"}\n'), 10000);
} else if (mode === "oversized") {
  process.stdout.write("x".repeat(1024 * 1024 + 1) + "\n");
} else if (mode === "invalid") {
  process.stdout.write("not-json\n");
} else if (mode === "crash") {
  process.stderr.write("fixture crash\n");
  process.exit(17);
} else {
  process.stdin.setEncoding("utf8");
  process.stdin.once("data", (input) => {
    const request = JSON.parse(input.trim());
    process.stdout.write(JSON.stringify({
      ok: true,
      result: request.method === "generate" ? "phase5-fixture" : { accepted: true },
    }) + "\n");
  });
}
