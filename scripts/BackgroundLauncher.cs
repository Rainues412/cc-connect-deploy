using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;

// GUI entry point: no terminal is allocated before PowerShell starts.
internal static class BackgroundLauncher
{
    [StructLayout(LayoutKind.Sequential)]
    private struct BasicLimits
    {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinWorkingSet, MaxWorkingSet;
        public uint ActiveProcesses;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)]
    private struct IoCounters { public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes; }
    [StructLayout(LayoutKind.Sequential)]
    private struct ExtendedLimits
    {
        public BasicLimits Basic;
        public IoCounters Io;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetInformationJobObject(IntPtr job, int kind, ref ExtendedLimits limits, uint size);
    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll")]
    private static extern bool CloseHandle(IntPtr handle);

    private static string Quote(string value)
    {
        var result = new StringBuilder("\"");
        int slashes = 0;
        foreach (char c in value)
        {
            if (c == '\\') { slashes++; continue; }
            result.Append('\\', c == '"' ? slashes * 2 + 1 : slashes);
            result.Append(c); slashes = 0;
        }
        result.Append('\\', slashes * 2);
        return result.Append('"').ToString();
    }

    [STAThread]
    private static int Main(string[] args)
    {
        bool notice = args.Length == 2 && args[0] == "notice";
        if (!notice && (args.Length != 1 || (args[0] != "monitor" && args[0] != "startup"))) return 2;
        IntPtr job = IntPtr.Zero;
        Process child = null;
        try
        {
            string root = Directory.GetParent(AppDomain.CurrentDomain.BaseDirectory.TrimEnd('\\')).FullName;
            string script = Path.Combine(root, notice ? "monitor\\show-notice.ps1" : args[0] == "monitor" ? "monitor\\token-monitor.ps1" : "startup\\start-cc-connect.ps1");
            if (!File.Exists(script)) return 3;
            if (args[0] == "monitor")
            {
                job = CreateJobObject(IntPtr.Zero, null);
                var limits = new ExtendedLimits();
                limits.Basic.Flags = 0x2000; // JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
                if (job == IntPtr.Zero || !SetInformationJobObject(job, 9, ref limits, (uint)Marshal.SizeOf(limits))) return 1;
            }
            child = Process.Start(new ProcessStartInfo
            {
                FileName = notice ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell\\v1.0\\powershell.exe") : BackgroundHostPath.PowerShell,
                Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File " + Quote(script) + (notice ? " -Body " + Quote(args[1]) : ""),
                WorkingDirectory = root,
                UseShellExecute = false,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden,
                RedirectStandardInput = args[0] == "monitor",
                RedirectStandardOutput = args[0] == "monitor",
                RedirectStandardError = args[0] == "monitor"
            });
            // Startup may create the persistent PM2 daemon, which must outlive this launcher.
            if (job != IntPtr.Zero && !AssignProcessToJobObject(job, child.Handle))
            {
                // A very short script can finish before assignment; preserve its result.
                if (child.HasExited) return child.ExitCode;
                child.Kill();
                return 1;
            }
            Task output = Task.FromResult(0), error = Task.FromResult(0);
            if (args[0] == "monitor")
            {
                child.StandardInput.Close();
                output = child.StandardOutput.BaseStream.CopyToAsync(Stream.Null);
                error = child.StandardError.BaseStream.CopyToAsync(Stream.Null);
            }
            child.WaitForExit();
            Task.WaitAll(output, error);
            return child.ExitCode;
        }
        catch
        {
            if (child != null) { try { if (!child.HasExited) child.Kill(); } catch { } }
            return 1;
        }
        finally
        {
            // Closing the job also ends the monitor if Task Scheduler stops this launcher.
            if (job != IntPtr.Zero) CloseHandle(job);
            if (child != null) child.Dispose();
        }
    }
}
