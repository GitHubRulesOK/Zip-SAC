# Zip-SAC
A collection of ZIP‑related utilities, including Windows‑native Self‑Archiving Containers (SACs).  
The concept itself is not new - it’s the continuation of a lineage that goes back more than 40 years. Early 1980's CP/M and early DOS: Developers sometimes shipped COM/EXE files with appended data, and the program unpacked itself. The more public "Grandfather Rights" could be ARC‑SEA (Self‑Extracting ARC). This produced .EXE files that: Contained the ARC archive, contained a tiny decompressor stub and ran on any DOS machine without needing ARC.EXE. Then later Phil Katz introduced PKSFX, a ZIP‑based self‑extracting EXE. This became the dominant SFX format from the 1990s.

TAR‑SAC
---
Is conceptually closer but not identical to the ARC‑SEA model because: TAR is a Windows‑native helper, not embedded inside the stub. The SAC stub does not implement TAR itself, it carries the control logic that repeatedly invokes TAR to unpack or repack the payload.

ZIP‑SAC  
---
Uses a model similar to the classic PKZIP/PKSFX self‑extracting executables. The SAC stub contains its own ZIP‑aware logic: it locates the appended ZIP payload, parses the local headers, unpacks modules, and can rebuild the archive. No external ZIP tool is required.  
This makes ZIP‑SAC a true self‑extracting ZIP container in the PKSFX tradition, where the stub is the ZIP engine and the appended ZIP is a standard payload.

[zip-it](https://github.com/GitHubRulesOK/Zip-SAC/blob/main/zip-it.cmd)
---
From https://github.com/GitHubRulesOK/MyNotes/blob/master/SMOPs.MD#zip-it-add-to-fileextx-or-filezip  
This is the one line extension tool for Windows TAR to try to provide the -a (add) or -u (update) missing functions.  
Windows 10+ TAR.exe can extract one or more files from zip based containers such as DocX or similar office files.  
However it cannot add a single file TO a DocX or similar ZIP based file or folder.  

Provided as a CMD file which can be edited to provide zip-it.exe in current folder.

[ListArc](https://github.com/GitHubRulesOK/MyNotes/blob/master/C%23/listarc.cmd)
---
A related 7-Zip addin utility "ListArc" can be found at https://github.com/GitHubRulesOK/MyNotes/blob/master/C%23/listarc.cmd . This allows in many cases to see a listing inside standard Zip (or some other) self extracting archive files. Most easily used as a right click "SendTo" as simpler than launch a console command.
![ListArc.png](https://github.com/GitHubRulesOK/MyNotes/blob/master/C%23/ListArc.png)
