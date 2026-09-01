import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Windows RAW spooler bridge implemented through the host PowerShell runtime.
/// It invokes Win32 OpenPrinter/StartDocPrinter/WritePrinter directly and does
/// not depend on a Flutter plugin or a browser runtime.
class WmnWindowsRawSpooler {
  const WmnWindowsRawSpooler();

  Future<void> write(String printerName, Uint8List bytes) async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows RAW spooler is available on Windows only.');
    }
    final name = printerName.trim();
    if (name.isEmpty) throw StateError('Windows printer name is required.');
    final temp = await File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}wmn_print_${DateTime.now().microsecondsSinceEpoch}.bin',
    ).create();
    await temp.writeAsBytes(bytes, flush: true);
    final script = _script(name, temp.path);
    try {
      final result = await Process.run(
        'powershell.exe',
        <String>['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
        stdoutEncoding: utf8,
        stderrEncoding: utf8,
      );
      if (result.exitCode != 0) {
        throw StateError('Windows RAW spooler failed: ${result.stderr}');
      }
    } finally {
      if (await temp.exists()) await temp.delete();
    }
  }

  String _script(String printerName, String path) {
    final printer = printerName.replaceAll("'", "''");
    final file = path.replaceAll("'", "''");
    return r'''
$src = @"
using System;
using System.Runtime.InteropServices;
public class WmnRawPrinter {
  [StructLayout(LayoutKind.Sequential, CharSet=CharSet.Ansi)] public class DOCINFOA {
    [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
    [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
    [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
  }
  [DllImport("winspool.Drv", EntryPoint="OpenPrinterA", SetLastError=true, CharSet=CharSet.Ansi)]
  public static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pd);
  [DllImport("winspool.Drv", SetLastError=true)] public static extern bool ClosePrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", EntryPoint="StartDocPrinterA", SetLastError=true, CharSet=CharSet.Ansi)]
  public static extern int StartDocPrinter(IntPtr hPrinter, int level, [In] DOCINFOA di);
  [DllImport("winspool.Drv", SetLastError=true)] public static extern bool EndDocPrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", SetLastError=true)] public static extern bool StartPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", SetLastError=true)] public static extern bool EndPagePrinter(IntPtr hPrinter);
  [DllImport("winspool.Drv", SetLastError=true)] public static extern bool WritePrinter(IntPtr hPrinter, byte[] pBytes, int dwCount, out int dwWritten);
  public static void Send(string printer, byte[] bytes) {
    IntPtr h; if (!OpenPrinter(printer, out h, IntPtr.Zero)) throw new System.ComponentModel.Win32Exception();
    try {
      var di = new DOCINFOA(); di.pDocName="WMN Print Job"; di.pDataType="RAW";
      if (StartDocPrinter(h,1,di)==0) throw new System.ComponentModel.Win32Exception();
      try {
        if (!StartPagePrinter(h)) throw new System.ComponentModel.Win32Exception();
        try { int written; if (!WritePrinter(h,bytes,bytes.Length,out written) || written!=bytes.Length) throw new System.ComponentModel.Win32Exception(); }
        finally { EndPagePrinter(h); }
      } finally { EndDocPrinter(h); }
    } finally { ClosePrinter(h); }
  }
}
"@
Add-Type -TypeDefinition $src -Language CSharp
''' "[WmnRawPrinter]::Send('$printer',[IO.File]::ReadAllBytes('$file'))";
  }
}
