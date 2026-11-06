const CHUNK = 262144;

function decodeHex(chunks) {
  const output = [];
  let codes = [], value = 0, remaining = 0, minimum = 0;
  for (const hex of chunks) {
    for (let i = 0; i < hex.length; i += 2) {
      const byte = parseInt(hex.slice(i, i + 2), 16);
      if (remaining) {
        if ((byte & 0xc0) !== 0x80) throw new Error("The PR diff is not valid UTF-8 text.");
        value = (value << 6) | (byte & 0x3f);
        if (--remaining) continue;
        if (value < minimum || value > 0x10ffff || (value >= 0xd800 && value <= 0xdfff)) throw new Error("The PR diff is not valid UTF-8 text.");
      } else if (byte < 0x80) value = byte;
      else if (byte >= 0xc2 && byte <= 0xdf) { value = byte & 0x1f; remaining = 1; minimum = 0x80; continue; }
      else if (byte >= 0xe0 && byte <= 0xef) { value = byte & 0x0f; remaining = 2; minimum = 0x800; continue; }
      else if (byte >= 0xf0 && byte <= 0xf4) { value = byte & 7; remaining = 3; minimum = 0x10000; continue; }
      else throw new Error("The PR diff is not valid UTF-8 text.");
      if (value === 0) throw new Error("The PR diff contains NUL and cannot be displayed as text.");
      if (value <= 0xffff) codes.push(value);
      else { const scalar = value - 0x10000; codes.push(0xd800 + (scalar >> 10), 0xdc00 + (scalar & 0x3ff)); }
      if (codes.length >= 2048) { output.push(String.fromCharCode(...codes)); codes = []; }
    }
  }
  if (remaining) throw new Error("The PR diff ends in an incomplete UTF-8 sequence.");
  if (codes.length) output.push(String.fromCharCode(...codes));
  return output.join("");
}

// All commands and temporary files are on the captured target. No repository data is
// interpolated into shell source; the private directory is removed even on failure.
export async function readDiff(exec, target, item, current, onCreate, onCleanup) {
  const options = { cwd: target.cwd, on: target.machine };
  const first = await exec("sh", ["-c", "umask 077; mktemp -d /tmp/herdr-gh.XXXXXXXXXX"], options);
  if (first.code !== 0) throw new Error((first.stderr || first.stdout || `mktemp exited ${first.code}`).trim());
  const match = /^\s*(\/tmp\/herdr-gh\.[A-Za-z0-9]{10})\s*$/.exec(first.stdout);
  if (!match) throw new Error("Could not safely identify the target-side diff directory for reading and cleanup.");
  const directory = match[1];
  let result, failure;
  try {
    onCreate?.(directory);
    if (!current()) throw new Error("The selected PR changed while its diff was loading.");
    const script = 'gh pr diff "$2" --repo "$3" > "$1/diff" || exit $?; wc -c < "$1/diff"';
    const download = await exec("sh", ["-c", script, "herdr-gh", directory, String(item.number), `${item.host}/${item.owner}/${item.repo}`], options);
    if (download.code !== 0) throw new Error((download.stderr || download.stdout || `gh diff exited ${download.code}`).trim());
    const sizeText = download.stdout.trim();
    if (!/^\d+$/.test(sizeText)) throw new Error("Could not determine the complete PR diff size.");
    const size = Number(sizeText);
    if (!Number.isSafeInteger(size)) throw new Error("The PR diff size is unsupported.");
    const chunks = [];
    for (let offset = 0; offset < size; offset += CHUNK) {
      if (!current()) throw new Error("The selected PR changed while its diff was loading.");
      const script = 'dd if="$1/diff" of="$1/part" bs=262144 skip="$2" count=1 2>/dev/null || exit 1; od -An -v -tx1 "$1/part"';
      const response = await exec("sh", ["-c", script, "herdr-gh", directory, String(offset / CHUNK)], options);
      if (response.code !== 0) throw new Error((response.stderr || "Could not read the target-side diff chunk.").trim());
      const hex = response.stdout.replace(/\s/g, "");
      if (!/^[0-9a-f]*$/i.test(hex) || hex.length !== Math.min(CHUNK, size - offset) * 2)
        throw new Error("The target returned an incomplete diff chunk; refusing to display a partial diff.");
      chunks.push(hex);
    }
    result = decodeHex(chunks);
  } catch (error) { failure = error; }
  let cleanup;
  try { cleanup = await exec("sh", ["-c", 'rm -f "$1/diff" "$1/part" && rmdir "$1"', "herdr-gh", directory], options); }
  catch (error) {
    const failure = new Error(`Could not remove the private target-side diff directory ${directory}: ${String(error)}`);
    failure.cleanupFailed = true; throw failure;
  }
  if (cleanup.code !== 0) {
    const failure = new Error(`Could not remove the private target-side diff directory ${directory}: ${(cleanup.stderr || cleanup.stdout || `exit ${cleanup.code}`).trim()}`);
    failure.cleanupFailed = true; throw failure;
  }
  onCleanup?.(directory);
  if (failure) throw failure;
  return result;
}
