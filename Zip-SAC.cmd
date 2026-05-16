/*&cls&@echo off&rem       SEE THE NOTES BELOW

cd /d "%~dp0" & setlocal enabledelayedexpansion

set "CSC=%SystemRoot%\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if not exist "%CSC%" set "CSC=%SystemRoot%\Microsoft.NET\Framework\v4.0.30319\csc.exe"
if not exist "%CSC%" ( echo Compiler not found & pause & exit /b )
for %%I in ("%CSC%") do set "CSCDIR=%%~dpI"
set "PATH=%CSCDIR%;%PATH%"

"%CSC%" /nologo /optimize /platform:x86 /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll /r:System.IO.Compression.ZipFile.dll /out:"%~n0.exe" "%~0"
if errorlevel 1 ( echo Compilation failed & pause & exit /b 1 )

if not exist "%~dpn0.exe" echo "%~dpn0" not found, possibly compile failed.
if exist "%~dpn0.exe" echo Windows native CS Compilation as "%~n0.exe"succeeded
pause
exit /b

NOTES
-----
Recomended name "Zip-SAC"........Initial release 2026-05-16-01

This is a self‑compiling C# utility.
Run this .CMD file to compile Zip-SAC.exe.

The purpose is to build Self Archiving Containers based on zip file/folder format. Which can
allow to run a contained module. The zip content can be a data file or an executable app but
only one file can be run direct, so if more are needed the first must unpack others it needs.
*/
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Text;
using System.Collections.Generic;
using System.IO.Compression;

// Self Archiving Command (SAC) Module = A stub.exe for appending a ZIPped SACK of files in a tool bag or satchel.
class SAC
{
    static string self; static string selfName; static string selfBase;
    class Entry
    {
        public string Name; public uint Uncomp; public DateTime Stamp;
    }
    class HeaderInfo
    {
        public long HeaderStart; public long DataStart; public long NextOffset;
        public string Name; public uint Uncomp; public uint Comp; public DateTime Stamp;
    }
// --------
// MAIN
// --------
static void Main(string[] args)
{
    self = Assembly.GetExecutingAssembly().Location;
    selfName = Path.GetFileName(self);
    selfBase = Path.GetFileNameWithoutExtension(self);
    bool hasPayload = FindPayloadOffset(self) >= 0;
    string tempRoot = Path.Combine(Path.GetTempPath(), "SAC_work");
    if (args.Length == 0) { PrintUsage(!hasPayload); return; }
    // --------
    // Parse -s <target>
    // --------
    string target = self;   // ALWAYS the SOURCE EXE
    for (int i = 0; i < args.Length; i++)
    {
        // -s is basically experimental for adjusting Secondary/Slave versions so not really considered a core ability
        if (args[i].Equals("-s", StringComparison.OrdinalIgnoreCase))
        {
            if (i + 1 >= args.Length) { Console.WriteLine("Error: -s requires a filename"); return; }
            target = Path.GetFullPath(args[i + 1]);
            List<string> list = new List<string>(args); list.RemoveAt(i + 1); list.RemoveAt(i); args = list.ToArray();
            break;
        }
    }
    if (args.Length == 0) { PrintUsage(false); return; }
    bool isAdd  = args[0].Equals("-a", StringComparison.OrdinalIgnoreCase);
    bool isDel  = args[0].Equals("-d", StringComparison.OrdinalIgnoreCase);
    bool isRun  = !args[0].StartsWith("-");
    bool isList = args[0].Equals("-l", StringComparison.OrdinalIgnoreCase) || args[0].Equals("-v", StringComparison.OrdinalIgnoreCase);
    // --------
    // LIST MODE
    // --------
    if (isList) { RunList(target, args); return; }
    // --------
    // ADD MODE GUARD
    // --------
    if (isAdd && args.Length > 1)
    {
        for (int i = 1; i < args.Length; i++)
        {
            string pattern = args[i];
            // If pattern contains wildcards, DO NOT check File.Exists
            if (pattern.Contains("*") || pattern.Contains("?")) continue;
            if (!File.Exists(args[i])) { Console.WriteLine("SAC: ADD source not found: " + args[i]); return; }
        }
    }
    // --------
    // EMPTY SAC CHECK
    // --------
    if (!hasPayload && !isAdd){ Console.WriteLine("This \"" + selfName + "\" is EMPTY. Run: " + selfBase + " -a file.ext to initialise"); return; }
    // --------
    // NOT -A RULE
    // --------
    if (!isAdd)
    {
        string pattern = null;
        if (isRun)
            pattern = args[0];
        else if (isDel)
            pattern = args.Length > 1 ? args[1] : null;
        if (pattern == null) { Console.WriteLine("No module specified."); return; }
        bool found = false;
        foreach (Entry e in ScanLocalHeaders(target))
            if (WildcardMatch(e.Name, pattern))
                found = true;
        if (!found) { Console.WriteLine("No such module: " + pattern); return; }
    }
    // --------
    // COMMON PREP
    // --------
    Directory.CreateDirectory(tempRoot);
    if (!EnsureEmpty(tempRoot)) { Console.WriteLine("SAC: work folder not clean. Aborting."); return; }
    // TEMP COPY OF TARGET
    string tempTarget = Path.Combine(tempRoot, Path.GetFileName(target));
    File.Copy(target, tempTarget, true);
    // CLEAVE TEMP COPY
    string stubPath, zipPath;
    if (!CleaveSAC(tempTarget, tempRoot, out stubPath, out zipPath)) { Console.WriteLine("SAC is empty."); return; }
    // DELETE TEMP COPY AFTER CLEAVE
    try { File.Delete(tempTarget); } catch {}
    // UNPACK FOR ADD / DEL
    if (isAdd || isDel) { UnpackSAC(zipPath, tempRoot); }
    // --------
    // ADD
    // --------
    if (isAdd && args.Length > 1)
    {
        for (int i = 1; i < args.Length; i++)
        {
            string pattern = args[i]; string cmd = "copy /Y \"" + pattern + "\" \"" + tempRoot + "\\\"";
            int rc = RunDosOperation(Environment.CurrentDirectory, cmd);
            if (rc != 0) { Console.WriteLine("SAC: ADD failed for " + pattern); return; }
        }
        Rebuild(target, tempRoot, stubPath);
        return;
    }
    // --------
    // DEL
    // --------
    if (isDel && args.Length > 1)
    {
        string pattern = args[1]; string fullPattern = Path.Combine(tempRoot, pattern); string cmd = "del /Q \"" + fullPattern + "\"";
        int rc = RunDosOperation(tempRoot, cmd);
        if (rc != 0) { Console.WriteLine("SAC: DELETE failed for " + pattern); return; }
        Rebuild(target, tempRoot, stubPath);
        return;
    }
    // --------
    // RUN
    // --------
    if (isRun) { RunModule(target, args, tempRoot); return; }

// END MAIN
}
// --------
// HELPERS
// --------
// --------
// RUN MODULE
// --------
static void RunModule(string target, string[] args, string tempRoot)
{
    string runPattern = args[0];
    // 1. Scan ZIP ENTRIES for matching module names
    List<Entry> matches = new List<Entry>();
    foreach (Entry e in ScanLocalHeaders(target))
    {
        if (WildcardMatch(e.Name, runPattern)) matches.Add(e);
    }
    // 2. Validate match count
    if (matches.Count == 0) { Console.WriteLine("No such module: " + runPattern); return; }
    if (matches.Count > 1) { Console.WriteLine("Ambiguous module: " + runPattern); return; }
    string module = matches[0].Name;
    // 3. Prepare a work folder
    if (!EnsureEmpty(tempRoot)) { Console.WriteLine("SAC: work folder not clean. Aborting."); return; }
    // 4. CLEAVE + EXTRACT ONLY THE MATCHED MODULE (inlined ExtractSingle)
    string stubPath, zipPath;
    // Cleave SAC into stub + sac.zip
    if (!CleaveSAC(target, tempRoot, out stubPath, out zipPath)) { Console.WriteLine("SAC is empty."); return; }
    // Extract only the requested module
    bool found = false;
    using (ZipArchive za = ZipFile.OpenRead(zipPath))
    {
        foreach (ZipArchiveEntry e in za.Entries)
        {
            if (string.Equals(e.FullName, module, StringComparison.OrdinalIgnoreCase))
            {
                string outPath = Path.Combine(tempRoot, module); e.ExtractToFile(outPath, true); found = true; break;
            }
        }
    }
    if (!found) { Console.WriteLine("Module not found: " + module); return; }
    // 5. Build module path
    string modulePath = Path.Combine(tempRoot, module);
    string moduleArgs = args.Length > 1
        ? string.Join(" ", args, 1, args.Length - 1)
        : "";
    // 6. Run the module
    ProcessStartInfo psi = new ProcessStartInfo();
    psi.FileName = modulePath;
    psi.Arguments = moduleArgs;
    // IMPORTANT: allow Windows to use file associations (.vbs, .js, .cmd, .bat)
    psi.UseShellExecute = true;
    Process p = Process.Start(psi);
    p.WaitForExit();
}

static int RunDosOperation(string workingDir, string command)
{
    var psi = new ProcessStartInfo("cmd.exe", "/c " + command);
    psi.WorkingDirectory = workingDir;
    psi.UseShellExecute = false;
    psi.RedirectStandardOutput = true;
    psi.RedirectStandardError = true;
    var p = Process.Start(psi);
    string output = p.StandardOutput.ReadToEnd();
    string error  = p.StandardError.ReadToEnd();
    p.WaitForExit();
    if (output.Length > 0) Console.Write(output);
    if (error.Length  > 0) Console.Write(error);
    return p.ExitCode;
}

static long FindPayloadOffset(string path)
{
    using (FileStream fs = File.OpenRead(path))
    {
        byte[] sig = { (byte)'P', (byte)'K', 3, 4 };
        while (true)
        {
            long pos = FindNext(fs, sig);
            if (pos < 0) return -1;
            HeaderInfo h;   // <-- MUST be here, inside the loop, before the call
            if (TryReadLocalHeader(fs, pos, out h))
                return pos;
            fs.Position = pos + 1;
        }
    }
}

static ushort ReadU16(Stream s)
{
    int lo = s.ReadByte(); int hi = s.ReadByte(); if (hi < 0) return 0; return (ushort)(lo | (hi << 8));
}

static uint ReadU32(Stream s)
{
    int b0 = s.ReadByte(); int b1 = s.ReadByte(); int b2 = s.ReadByte(); int b3 = s.ReadByte();
    if (b3 < 0) return 0; return (uint)(b0 | (b1 << 8) | (b2 << 16) | (b3 << 24));
}

    static bool TryReadLocalHeader(FileStream fs, long pos, out HeaderInfo info)
    {
        info = null;
        fs.Position = pos + 4; fs.Position += 2; // skip PK 03 04 and Version
        ushort flags   = ReadU16(fs); ushort compMethod = ReadU16(fs); ushort time = ReadU16(fs); ushort date = ReadU16(fs);
        uint crc       = ReadU32(fs); uint compSize  = ReadU32(fs); uint uncompSize = ReadU32(fs);
        ushort nameLen = ReadU16(fs); ushort extraLen = ReadU16(fs);
        if (compMethod != 0 && compMethod != 8) return false;
        if (nameLen == 0 || nameLen > 260) return false;
        long afterHeader = fs.Position + nameLen + extraLen;
        if (afterHeader > fs.Length) return false;
        byte[] nameBytes = new byte[nameLen];
        fs.Read(nameBytes, 0, nameLen);
        string name = Encoding.UTF8.GetString(nameBytes);
        if (string.IsNullOrWhiteSpace(name)) return false;
        fs.Position += extraLen;
        long dataStart = fs.Position;
        if ((flags & 0x0008) != 0)
        {
            long dd = FindNext(fs, new byte[] { (byte)'P', (byte)'K', 7, 8 });
            if (dd < 0 || dd + 16 > fs.Length) return false;
            fs.Position = dd + 4;
            crc = ReadU32(fs); compSize = ReadU32(fs); uncompSize = ReadU32(fs);
            fs.Position = dd + 16;
        }
        else
        {
            if (compSize > fs.Length - fs.Position) return false;
            fs.Position += compSize;
        }
        int day = date & 0x1F; int month = (date >> 5) & 0x0F; int year = ((date >> 9) & 0x7F) + 1980;
        int sec = (time & 0x1F) * 2; int min  = (time >> 5) & 0x3F; int hour = (time >> 11) & 0x1F;
        DateTime stamp;
        try { stamp = new DateTime(year, month, day, hour, min, sec); }
        catch { stamp = DateTime.MinValue; }
        info = new HeaderInfo { HeaderStart = pos, DataStart = dataStart, NextOffset = fs.Position, Name = name, Uncomp = uncompSize, Comp = compSize, Stamp = stamp };
        return true;
    }
    // --------
    // LIST
    // --------
    static void RunList(string target, string[] args)
    {
        bool verbose = false;
        string pattern = null;
        for (int i = 0; i < args.Length; i++)
        {
            if (args[i].Equals("-v", StringComparison.OrdinalIgnoreCase)) verbose = true;
            else if (!args[i].Equals("-l", StringComparison.OrdinalIgnoreCase)) pattern = args[i];
        }
        foreach (Entry e in ScanLocalHeaders(target))
        {
            if (pattern != null && !WildcardMatch(e.Name, pattern)) continue;
            if (!verbose) Console.WriteLine(e.Name);
            else Console.WriteLine( "{0,-30}  {1,10}  {2}", e.Name, e.Uncomp, e.Stamp.ToString("yyyy-MM-dd HH:mm:ss") );
        }
    }

    static bool WildcardMatch(string text, string pattern)
    {
        int t = 0, p = 0, star = -1, match = 0;
        while (t < text.Length)
        {
            if (p < pattern.Length && (pattern[p] == '?' || char.ToLower(pattern[p]) == char.ToLower(text[t]))) { p++; t++; }
            else if (p < pattern.Length && pattern[p] == '*') { star = p++; match = t; }
            else if (star != -1) { p = star + 1; t = ++match; }
            else { return false; }
        }
        while (p < pattern.Length && pattern[p] == '*') p++;
        return p == pattern.Length;
    }
    // --------
    // EXTRACT
    // --------
static IEnumerable<Entry> ScanLocalHeaders(string path)
{
    using (FileStream fs = File.OpenRead(path))
    {
        byte[] sig = { (byte)'P', (byte)'K', 3, 4 };
        while (true)
        {
            long pos = FindNext(fs, sig);
            if (pos < 0) yield break;
            HeaderInfo h;   // <-- MUST be here, inside the loop, before the call
            if (TryReadLocalHeader(fs, pos, out h))
            {
                yield return new Entry { Name = h.Name, Uncomp = h.Uncomp, Stamp  = h.Stamp };
            }
            else { fs.Position = pos + 1; }
        }
    }
}

static long FindNext(FileStream fs, byte[] sig)
{
    int b; int matched = 0; long start = fs.Position;
    while ((b = fs.ReadByte()) != -1)
    {
        if (b == sig[matched]) { matched++; if (matched == sig.Length) return fs.Position - sig.Length; }
        else { if (matched > 0) { fs.Position = fs.Position - matched + 1; matched = 0; } }
    }
    return -1;
}

    // --------
    // Ensure work folder is empty
    // --------
    static bool EnsureEmpty(string tempRoot, int maxAttempts = 5)
    {
        Directory.CreateDirectory(tempRoot);
        for (int attempt = 1; attempt <= maxAttempts; attempt++)
        {
        // Delete files
        foreach (string f in Directory.GetFiles(tempRoot)) { try { File.Delete(f); } catch { } }
        // Delete directories
        foreach (string d in Directory.GetDirectories(tempRoot)) { try { Directory.Delete(d, true); } catch { } }
        // Check again
        if (Directory.GetFiles(tempRoot).Length == 0 && Directory.GetDirectories(tempRoot).Length == 0) return true;
        Thread.Sleep(100);
        }
        return Directory.GetFiles(tempRoot).Length == 0 && Directory.GetDirectories(tempRoot).Length == 0;
    }

static bool CleaveSAC(string target, string tempRoot, out string stubPath, out string zipPath)
{
    stubPath = Path.Combine(tempRoot, "starter.exe");
    zipPath  = Path.Combine(tempRoot, "sac.zip");
    long offset = FindPayloadOffset(target);
    using (FileStream src = File.OpenRead(target))
    {
        // --------
        // CASE 1: NO ZIP PAYLOAD
        // --------
        if (offset < 0)
        {
            // Entire EXE is the stub
            File.Copy(target, stubPath, true);
            // Ensure no ZIP file exists
            if (File.Exists(zipPath)) File.Delete(zipPath);
            return true;
        }
        // --------
        // CASE 2: ZIP PAYLOAD EXISTS
        // --------
        // Write stub
        using (FileStream dst = File.Create(stubPath))
        {
            byte[] buffer = new byte[8192];
            long remaining = offset;
            while (remaining > 0)
            {
                int read = src.Read(buffer, 0, (int)Math.Min(buffer.Length, remaining));
                if (read <= 0) break;
                dst.Write(buffer, 0, read);
                remaining -= read;
            }
        }
        // Write ZIP tail
        using (FileStream dst = File.Create(zipPath)) { src.CopyTo(dst); }
    }
    return true;
}
// --------
// Unpack full SAC payload from zipPath into tempRoot
// --------
static void UnpackSAC(string zipPath, string tempRoot)
{
    if (!File.Exists(zipPath)) return; // no payload yet
    using (ZipArchive za = ZipFile.OpenRead(zipPath))
    {
        foreach (ZipArchiveEntry e in za.Entries)
        {
            string outPath = Path.Combine(tempRoot, e.FullName); string dir = Path.GetDirectoryName(outPath);
            if (!string.IsNullOrEmpty(dir)) Directory.CreateDirectory(dir);
            e.ExtractToFile(outPath, true);
        }
    }
    // Remove sac.zip so it never becomes "content"
    File.Delete(zipPath);
}
// --------
// Rebuild target from stub + tempRoot
// --------
static void Rebuild(string target, string tempRoot, string stubPath)
{
  string newExe = Path.Combine(tempRoot, "SAC-new.exe"); string newZip = Path.Combine(tempRoot, "new-SAC.zip");
  if (!File.Exists(stubPath)) { Console.WriteLine("SAC: missing stub; cannot rebuild."); return; }
  // 1. Build ZIP payload (exclude stub + build artifacts)
    {
    // Build exclusion set
    HashSet<string> exclude = new HashSet<string>();
    exclude.Add(Path.GetFileName(stubPath).ToLowerInvariant());
    exclude.Add("new-sac.zip");
    exclude.Add("sac-new.exe");
    exclude.Add("starter.exe");
    if (File.Exists(newZip)) File.Delete(newZip);
    using (FileStream zipStream = new FileStream(newZip, FileMode.Create))
    using (ZipArchive archive = new ZipArchive(zipStream, ZipArchiveMode.Create))
      {
        foreach (string file in Directory.GetFiles(tempRoot))
        {
            string name = Path.GetFileName(file).ToLowerInvariant();
            if (exclude.Contains(name)) continue;
            archive.CreateEntryFromFile(file, Path.GetFileName(file), CompressionLevel.Optimal);
        }
      }
    }
  // 2. Copy stub fresh (minimal cleaved stub)
    File.Copy(stubPath, newExe, true);
  // 3. Append ZIP cleanly
    using (FileStream outStream = new FileStream(newExe, FileMode.Open, FileAccess.Write))
      {
        outStream.Seek(0, SeekOrigin.End);
        using (FileStream zipStream = new FileStream(newZip, FileMode.Open, FileAccess.Read))
        {
            zipStream.CopyTo(outStream);
        }
      }
    string vbs = Path.Combine(Path.GetTempPath(), "SAC_update.vbs");
    File.WriteAllText(vbs,
    "On Error Resume Next\n" +
    "WScript.Sleep 1000\n" +
    "Set fso = CreateObject(\"Scripting.FileSystemObject\")\n" +
    "src = \"" + newExe.Replace("\"", "\"\"") + "\"\n" +
    "dst = \"" + target.Replace("\"", "\"\"") + "\"\n" +
    "tempdir = \"" + Path.GetTempPath().Replace("\"", "\"\"") + "\"\n" +
//    "fso.CopyFile \"" + newExe + "\", \"" + target + "\", True\n" +
    "fso.CopyFile src, dst, True\n" +
    "title = \"Update SelfArchivingCommander\"\n" +
//    "title = fso.GetFile(WScript.ScriptFullName).Name\n" +
    "If Err.Number <> 0 Then\n" +
    "  MsgBox \"I attempted a copy, but the OS reported an error:\" & vbCrLf & Err.Description, 48, \"Updater\"\n" +
    "Else\n" +
//    "  If fso.FileExists(\"" + target + "\") Then\n" +
//    "    Set src = fso.GetFile(\"" + newExe + "\")\n" +
//    "    Set dst = fso.GetFile(\"" + target + "\")\n" +
//    "    If src.Size = dst.Size Then\n" +
    "  If fso.FileExists(dst) Then\n" +
    "    Set s = fso.GetFile(src)\n" +
    "    Set d = fso.GetFile(dst)\n" +
    "    If s.Size = d.Size Then\n" +
    "      MsgBox \"Copy completed successfully.\", 64, title\n" +
    "    Else\n" +
    "      MsgBox \"I attempted a copy, but verification failed.\", 48, title\n" +
    "    End If\n" +
    "  Else\n" +
    "    MsgBox \"I attempted a copy, but the target file does not exist.\", 48, title\n" +
    "  End If\n" +
    "End If\n" +
    "If fso.FolderExists(tempdir) Then\n" +
//    "  On Error Resume Next\n" +
//    "  fso.DeleteFolder tempdir, True\n" +
//    "    newname = tempdir & "_old_" & Replace(CStr(Now), ":", "-")\n" +
    "    newname = tempdir & \"_old_\" & Year(Now) & \"-\" & Month(Now) & \"-\" & Day(Now) & \"_\" & Hour(Now) & \"-\" & Minute(Now) & \"-\" & Second(Now)\n" +
    "    On Error Resume Next\n" +
    "    fso.MoveFolder tempdir, newname\n" +
    "      For i = 1 To 10\n" +
    "          On Error Resume Next\n" +
//    "          fso.DeleteFolder tempdir, True\n" +
    "          fso.DeleteFolder newname, True\n" +
    "          If Err.Number = 0 Then Exit For\n" +
    "          Err.Clear\n" +
    "          WScript.Sleep 500\n" +
    "      Next\n" +
    "End If\n" +
//  ' Delete the worker script itself
    "fso.DeleteFile WScript.ScriptFullName\n"
    );
    var psi = new ProcessStartInfo
    {
    FileName = "wscript.exe",
    Arguments = "\"" + vbs + "\"",
    WindowStyle = ProcessWindowStyle.Hidden,
    CreateNoWindow = true,
    UseShellExecute = false
    };
    Process.Start(psi);
    Environment.Exit(0);
}
    // --------
    // Usage
    // --------
    static void PrintUsage(bool isEMPTY)
    {
        Console.WriteLine("\n Self Archiving Carrier (Stub.exe + zip = SAC.exe)\n");
        Console.WriteLine(" Usage: " + selfBase + " [options] [Module (must include .ext)] [args]\n");
        Console.WriteLine("  Options            Default is to call/run the file module");
        Console.WriteLine("  -l [pattern]       List modules (can be any file type app's or data/doc's)");
        Console.WriteLine("  -v [pattern]       Verbose list with source size and dates");
        Console.WriteLine("  -a file.ext        Add module(s) to archive (supports wildcards)");
        Console.WriteLine("  -d file.ext        Delete module(s) (supports wildcards)");
        Console.WriteLine("  -s other.exe [...] Beware this is more experimental to adjust other SAC.exe");
        if (isEMPTY) { Console.WriteLine(); Console.WriteLine("This \"" + selfName + "\" is EMPTY. Use: " + selfBase + " -a file.ext to add first content"); }
    }
} // end class SAC
