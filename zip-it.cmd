REM from https://github.com/GitHubRulesOK/MyNotes/blob/master/SMOPs.MD#zip-it-add-to-fileextx-or-filezip
REM this is the one line extension tool for Windows TAR to provide the -a (add) or -u (update) missing functions
REM run this CMD file should (if all is well) provide zip-it.exe in current folder. Requires Windows csc.exe which is usually found on Windows 7+.
REM
echo using System;using System.IO.Compression;class Z{static void Main(string^[^] a){if(a.Length^<3){Console.WriteLine("Usage: zip-it <zipfile.ext> <entry> <file to add>");return;}using(var z=ZipFile.Open(a^[0^],ZipArchiveMode.Update)){var e=z.GetEntry(a^[1^]);if(e!=null)e.Delete();z.CreateEntryFromFile(a^[2^],a^[1^]);}}} > "%TMP%\zip-it.cs"  && "C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe" /nologo /platform:x86 /r:System.IO.Compression.dll /r:System.IO.Compression.FileSystem.dll /out:"%CD%\zip-it.exe" "%TMP%\zip-it.cs"  && del "%TMP%\zip-it.cs"
