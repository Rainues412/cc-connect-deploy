using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Threading.Tasks;

// Windows GUI subsystem: no console is allocated for cc-connect's outer command.
internal static class ClaudeGuardLauncher
{
    private static async Task Forward(Stream source, Stream target)
    {
        byte[] buffer = new byte[8192];
        int length;
        while ((length = await source.ReadAsync(buffer, 0, buffer.Length)) != 0)
        {
            await target.WriteAsync(buffer, 0, length);
            await target.FlushAsync();
        }
    }

    private static string Quote(string value)
    {
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            if (c == '"') result.Append('\\', slashes * 2 + 1);
            else result.Append('\\', slashes);
            result.Append(c); slashes = 0;
        }
        result.Append('\\', slashes * 2);
        return result.Append('"').ToString();
    }

    [STAThread]
    private static int Main(string[] args)
    {
        Process child = null;
        try
        {
            string root = Directory.GetParent(AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\')).FullName;
            string script = Path.Combine(root, "scripts", "claude-image-guard.cjs");
            var info = new ProcessStartInfo
            {
                FileName = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles), "nodejs", "node.exe"),
                Arguments = Quote(script) + " " + string.Join(" ", args.Select(Quote)),
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardInput = true,
                RedirectStandardOutput = true,
                RedirectStandardError = true
            };
            child = Process.Start(info);
            var input = Forward(Console.OpenStandardInput(), child.StandardInput.BaseStream);
            input.ContinueWith(t => { try { child.StandardInput.Close(); } catch { } });
            var output = Forward(child.StandardOutput.BaseStream, Console.OpenStandardOutput());
            var error = Forward(child.StandardError.BaseStream, Console.OpenStandardError());
            child.WaitForExit();
            Task.WaitAll(output, error);
            return child.ExitCode;
        }
        catch
        {
            try { Console.Error.WriteLine("Hidden Claude guard launcher failed."); } catch { }
            if (child != null) { try { child.Kill(); } catch { } }
            return 1;
        }
        finally { if (child != null) child.Dispose(); }
    }
}
