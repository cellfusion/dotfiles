import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

// Paseo の daemon はデスクトップアプリから起動されるため、ログインシェルの PATH を
// 継承するとは限らない。Homebrew の既定の場所を明示的に足す。
const SEARCH_PATH = ["/opt/homebrew/bin", "/usr/local/bin", process.env.PATH ?? ""]
  .filter((entry) => entry.length > 0)
  .join(":");

/** shell を経由せずにコマンドを実行し、標準出力を返す。 */
export async function runCommand(file: string, args: string[], cwd: string): Promise<string> {
  const { stdout } = await execFileAsync(file, args, {
    cwd,
    env: { ...process.env, PATH: SEARCH_PATH },
    maxBuffer: 8 * 1024 * 1024,
  });
  return stdout;
}
