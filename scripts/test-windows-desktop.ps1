# First build: flutter build windows --release --target test/support/windows_desktop_smoke.dart
# This harness sends native Windows input to its own Flutter window only.
param([string]$Executable = 'build/windows/x64/runner/Release/mario.exe')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$exe = (Resolve-Path (Join-Path $root $Executable)).Path
$runDir = Join-Path $root ('build/windows-smoke-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runDir | Out-Null
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class MarioSmokeInput {
 public delegate bool Callback(IntPtr h, IntPtr p);
 [DllImport("user32.dll")] public static extern bool EnumWindows(Callback c, IntPtr p);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
 [DllImport("user32.dll")] public static extern IntPtr FindWindowEx(IntPtr p, IntPtr a, string c, string t);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, UIntPtr w, IntPtr l);
 [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint c, uint t);
 [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out Rect r);
 [StructLayout(LayoutKind.Sequential)] public struct Rect { public int left,top,right,bottom; }
 public static IntPtr View(uint target) {
   IntPtr found=IntPtr.Zero;
   EnumWindows((h,p)=>{uint id;GetWindowThreadProcessId(h,out id);
     if(id==target){var v=FindWindowEx(h,IntPtr.Zero,"FLUTTERVIEW",null);if(v!=IntPtr.Zero){found=v;return false;}}
     return true;},IntPtr.Zero);
   return found;
 }
}
'@
function Read-Result {
    $path = Join-Path $runDir 'smoke-result.json'
    if (Test-Path $path) {
        try { return Get-Content -Raw $path | ConvertFrom-Json } catch { return $null }
    }
}
function Wait-Result([scriptblock]$Condition, [string]$Description) {
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    do {
        $result = Read-Result
        if ($result -and $result.error) { throw $result.error }
        if ($result -and (& $Condition $result)) { Write-Output "Passed: $Description"; return }
        if ($app.HasExited) { throw "Test app exited: $($app.ExitCode)" }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out: $Description. Last result: $($result | ConvertTo-Json -Depth 10 -Compress)"
}
function Set-Phase([string]$Phase) {
    Set-Content (Join-Path $runDir 'smoke-command.txt') $Phase
    Wait-Result { param($r) $r.phase -eq $Phase } "phase $Phase"
    Start-Sleep -Milliseconds 300
}
function Send-Text([string]$Text) {
    foreach ($character in $Text.ToCharArray()) {
        $key = [uint32][char]([string]$character).ToUpperInvariant()
        $data = 1 -bor ([MarioSmokeInput]::MapVirtualKey($key, 0) -shl 16)
        [MarioSmokeInput]::PostMessage($view, 0x100, [UIntPtr]$key, [IntPtr]$data) | Out-Null
        [MarioSmokeInput]::PostMessage($view, 0x101, [UIntPtr]$key, [IntPtr]($data -bor 0xC0000000L)) | Out-Null
        Start-Sleep -Milliseconds 100
    }
}
$app = Start-Process -FilePath $exe -WorkingDirectory $runDir -WindowStyle Hidden -PassThru -RedirectStandardError (Join-Path $runDir 'stderr.log')
try {
    Wait-Result { param($r) $r.phase -eq 'field' } 'app startup'
    $view = [MarioSmokeInput]::View($app.Id)
    if ($view -eq [IntPtr]::Zero) { throw 'Flutter view missing' }
    Send-Text 'fieldinput'
    Wait-Result { param($r) $r.field -eq 'fieldinput' } 'native text-field typing'
    Set-Phase 'editor'
    Send-Text 'editorinput'
    Wait-Result { param($r) $r.editor.document.children[0].data.delta[0].insert -eq 'editorinput' } 'native note-editor typing'
    Set-Phase 'preview'
    Wait-Result { param($r) $r.previewTitle -eq 'MARIO_PREVIEW_READY' } 'HTML preview load and callbacks'
    Set-Phase 'capture'
    Add-Type -AssemblyName System.Drawing
    $picture = [System.Drawing.Bitmap]::FromFile((Join-Path $runDir 'smoke-preview.png'))
    try {
        $pixel = $picture.GetPixel([int]($picture.Width / 2), [int]($picture.Height / 2))
        if ($pixel.G -lt 240 -or $pixel.R -gt 20 -or $pixel.B -gt 20) { throw 'Preview texture did not render the green HTML background' }
    } finally { $picture.Dispose() }
    Write-Output 'Passed: HTML pixels rendered in the Flutter texture'
    $rect = New-Object MarioSmokeInput+Rect
    [MarioSmokeInput]::GetClientRect($view, [ref]$rect) | Out-Null
    $point = ([int]($rect.right * 0.75)) -bor (30 -shl 16)
    [MarioSmokeInput]::PostMessage($view, 0x201, [UIntPtr][uint32]1, [IntPtr]$point) | Out-Null
    [MarioSmokeInput]::PostMessage($view, 0x202, [UIntPtr]::Zero, [IntPtr]$point) | Out-Null
    Start-Sleep -Milliseconds 500
    Send-Text 'browserinput'
    Wait-Result { param($r) $r.previewTitle -eq 'INPUT:browserinput' } 'native typing inside HTML preview'
    Set-Phase 'editor'
    Send-Text 'after'
    Wait-Result { param($r) $r.editor.document.children[0].data.delta[0].insert -eq 'aftereditorinput' } 'typing after leaving preview'
    $children = Get-CimInstance Win32_Process -Filter "name='mario.exe'" | Where-Object ParentProcessId -EQ $app.Id
    foreach ($child in $children) {
        if ([MarioSmokeInput]::View($child.ProcessId) -ne [IntPtr]::Zero) { throw 'CEF subprocess created an extra Mario window' }
    }
    Write-Output 'Passed: CEF subprocesses have no Flutter windows'
    Write-Output "Native smoke evidence: $runDir"
} finally {
    Get-CimInstance Win32_Process -Filter "name='mario.exe'" |
        Where-Object { $_.ProcessId -eq $app.Id -or $_.ParentProcessId -eq $app.Id } |
        ForEach-Object { Stop-Process -Id $_.ProcessId -ErrorAction SilentlyContinue }
}
