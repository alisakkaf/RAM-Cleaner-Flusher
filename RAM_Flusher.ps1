# =========================================================================
#          RAM CLEANER & FLUSHER v1.0 (Pro Edition)
# =========================================================================
# Created & Developed By: AliSakkaf (By AliSakkaf)
# GitHub:   https://github.com/alisakkaf
# Facebook: https://www.facebook.com/AliSakkaf.Dev/
# =========================================================================

# Ensure console supports Unicode block characters
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Clear-Host

# 1. Admin Privileges Elevation Check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host "   [!] ADMINISTRATIVE PRIVILEGES REQUIRED" -ForegroundColor Red
    Write-Host "   This optimizer needs administrative privileges to clean system memory lists." -ForegroundColor White
    Write-Host "   Attempting to restart with Administrator permissions..." -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Red
    try {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    }
    catch {
        Write-Host "[-] Elevation failed. Please run this script as Administrator manually." -ForegroundColor Red
        Read-Host "Press Enter to exit..."
    }
    Exit
}

# 2. C# Win32 Memory API Wrapper (C# 2.0 compatible for maximum Windows 7/8/10/11 compatibility)
$Win32Code = @"
using System;
using System.Runtime.InteropServices;
using System.Diagnostics;

public class Win32Memory {
    public const uint STATUS_SUCCESS = 0;
    
    private const int TOKEN_ADJUST_PRIVILEGES = 0x0020;
    private const int TOKEN_QUERY = 0x0008;
    private const int SE_PRIVILEGE_ENABLED = 0x00000002;
    private const string SE_PROFILE_SINGLE_PROCESS_NAME = "SeProfileSingleProcessPrivilege";
    private const string SE_INCREASE_QUOTA_NAME = "SeIncreaseQuotaPrivilege";

    private const int SystemMemoryListInformation = 80;

    [DllImport("ntdll.dll", SetLastError = true)]
    public static extern uint NtSetSystemInformation(
        int SystemInformationClass,
        IntPtr SystemInformation,
        int SystemInformationLength
    );

    [DllImport("psapi.dll", SetLastError = true)]
    public static extern bool EmptyWorkingSet(IntPtr hProcess);
    
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool SetProcessWorkingSetSize(IntPtr hProcess, IntPtr dwMinimumWorkingSetSize, IntPtr dwMaximumWorkingSetSize);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern IntPtr OpenProcess(uint processAccess, bool bInheritHandle, int processId);

    [DllImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    public static extern bool CloseHandle(IntPtr hObject);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    public struct MEMORYSTATUSEX
    {
        public uint dwLength;
        public uint dwMemoryLoad;
        public ulong ullTotalPhys;
        public ulong ullAvailPhys;
        public ulong ullTotalPageFile;
        public ulong ullAvailPageFile;
        public ulong ullTotalVirtual;
        public ulong ullAvailVirtual;
        public ulong ullAvailExtendedVirtual;
    }

    [return: MarshalAs(UnmanagedType.Bool)]
    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    public static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX lpBuffer);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool OpenProcessToken(IntPtr ProcessHandle, int DesiredAccess, out IntPtr TokenHandle);

    [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Auto)]
    private static extern bool LookupPrivilegeValue(string lpSystemName, string lpName, out long lpLuid);

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    internal struct LUID_AND_ATTRIBUTES
    {
        public long Luid;
        public int Attributes;
    }

    [StructLayout(LayoutKind.Sequential, Pack = 4)]
    internal struct TOKEN_PRIVILEGES
    {
        public int PrivilegeCount;
        public LUID_AND_ATTRIBUTES Privileges;
    }

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern bool AdjustTokenPrivileges(
        IntPtr TokenHandle,
        bool DisableAllPrivileges,
        ref TOKEN_PRIVILEGES NewState,
        int BufferLength,
        IntPtr PreviousState,
        IntPtr ReturnLength
    );

    public static bool EnablePrivilege(string privilegeName) {
        IntPtr tokenHandle = IntPtr.Zero;
        try {
            if (!OpenProcessToken(Process.GetCurrentProcess().Handle, TOKEN_ADJUST_PRIVILEGES | TOKEN_QUERY, out tokenHandle)) {
                return false;
            }
            long luid;
            if (!LookupPrivilegeValue(null, privilegeName, out luid)) {
                return false;
            }
            TOKEN_PRIVILEGES tp = new TOKEN_PRIVILEGES();
            tp.PrivilegeCount = 1;
            tp.Privileges = new LUID_AND_ATTRIBUTES();
            tp.Privileges.Luid = luid;
            tp.Privileges.Attributes = SE_PRIVILEGE_ENABLED;

            return AdjustTokenPrivileges(tokenHandle, false, ref tp, 0, IntPtr.Zero, IntPtr.Zero);
        } catch {
            return false;
        } finally {
            if (tokenHandle != IntPtr.Zero) CloseHandle(tokenHandle);
        }
    }

    public static bool EnableRequiredPrivileges() {
        bool p1 = EnablePrivilege(SE_PROFILE_SINGLE_PROCESS_NAME);
        bool p2 = EnablePrivilege(SE_INCREASE_QUOTA_NAME);
        return p1 || p2;
    }

    public static uint PurgeMemoryList(int command) {
        IntPtr commandPtr = Marshal.AllocHGlobal(sizeof(int));
        Marshal.WriteInt32(commandPtr, command);
        try {
            return NtSetSystemInformation(SystemMemoryListInformation, commandPtr, sizeof(int));
        } catch {
            return 0xC0000001; // STATUS_UNSUCCESSFUL
        } finally {
            Marshal.FreeHGlobal(commandPtr);
        }
    }

    public static bool ForceEmpty(IntPtr hProcess) {
        bool success = EmptyWorkingSet(hProcess);
        if (!success) { 
            success = SetProcessWorkingSetSize(hProcess, (IntPtr)(-1), (IntPtr)(-1)); 
        }
        return success;
    }

    public static MEMORYSTATUSEX GetMemoryStatus() {
        MEMORYSTATUSEX memStatus = new MEMORYSTATUSEX();
        memStatus.dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
        GlobalMemoryStatusEx(ref memStatus);
        return memStatus;
    }
}
"@

# 3. Add Type checking to avoid session redefinition crash
$Type = [System.Type]::GetType("Win32Memory")
if ($null -eq $Type) {
    try {
        Add-Type -TypeDefinition $Win32Code -ErrorAction Stop
    }
    catch {
        Write-Host "[-] Critical Error: Failed to compile Win32 Core Wrappers." -ForegroundColor Red
        Write-Host $_.Exception.Message -ForegroundColor Yellow
        Read-Host "Press Enter to exit..."
        Exit
    }
}

# Enable required privileges
[Win32Memory]::EnableRequiredPrivileges() | Out-Null

# 4. Helper Functions for formatting and status
function Get-MemoryMetrics {
    $status = [Win32Memory]::GetMemoryStatus()
    $totalPhysBytes = $status.ullTotalPhys
    $availPhysBytes = $status.ullAvailPhys
    $usedPhysBytes = $totalPhysBytes - $availPhysBytes
    
    $totalPhysMB = [Math]::Round($totalPhysBytes / 1MB, 2)
    $availPhysMB = [Math]::Round($availPhysBytes / 1MB, 2)
    $usedPhysMB = [Math]::Round($usedPhysBytes / 1MB, 2)
    
    $totalPhysGB = [Math]::Round($totalPhysBytes / 1GB, 2)
    $availPhysGB = [Math]::Round($availPhysBytes / 1GB, 2)
    $usedPhysGB = [Math]::Round($usedPhysBytes / 1GB, 2)
    
    $load = $status.dwMemoryLoad
    
    return [PSCustomObject]@{
        TotalBytes = $totalPhysBytes
        AvailBytes = $availPhysBytes
        UsedBytes  = $usedPhysBytes
        TotalMB    = $totalPhysMB
        AvailMB    = $availPhysMB
        UsedMB     = $usedPhysMB
        TotalGB    = $totalPhysGB
        AvailGB    = $availPhysGB
        UsedGB     = $usedPhysGB
        Load       = $load
    }
}

function Format-MemorySize {
    param(
        [double]$bytes
    )
    $mb = [Math]::Round($bytes / 1MB, 2)
    $gb = [Math]::Round($bytes / 1GB, 2)
    return "{0:N2} GB ({1:N2} MB)" -f $gb, $mb
}

function Get-StandbyMemoryBytes {
    try {
        $perfMem = Get-CimInstance Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
        if ($null -eq $perfMem) {
            $perfMem = Get-WmiObject Win32_PerfFormattedData_PerfOS_Memory -ErrorAction SilentlyContinue
        }
        if ($null -ne $perfMem) {
            $core = 0
            $normal = 0
            $reserve = 0
            if ($perfMem.StandbyCacheCoreBytes) { $core = [double]$perfMem.StandbyCacheCoreBytes }
            if ($perfMem.StandbyCacheNormalPriorityBytes) { $normal = [double]$perfMem.StandbyCacheNormalPriorityBytes }
            if ($perfMem.StandbyCacheReserveBytes) { $reserve = [double]$perfMem.StandbyCacheReserveBytes }
            return ($core + $normal + $reserve)
        }
    }
    catch {}
    return 0
}

function Get-ProgressBar {
    param(
        [int]$percentage
    )
    $totalBlocks = 15
    $filledBlocks = [Math]::Round(($percentage / 100) * $totalBlocks)
    $emptyBlocks = $totalBlocks - $filledBlocks
    
    $bar = ""
    for ($i = 0; $i -lt $filledBlocks; $i++) { $bar += "#" }
    for ($i = 0; $i -lt $emptyBlocks; $i++) { $bar += "-" }
    return "[$bar] $percentage%"
}

function Write-MenuOption {
    param(
        [string]$number,
        [string]$text,
        [string]$numColor = "Cyan"
    )
    Write-Host "  " -NoNewline
    Write-Host "[$number] " -ForegroundColor $numColor -NoNewline
    Write-Host $text -ForegroundColor White
}

function Start-SyncDelay {
    param([int]$milliseconds = 1500)
    Write-Host ""
    Write-Host "[*] Status: " -NoNewline -ForegroundColor White
    Write-Host "Waiting for Windows Memory Manager to synchronize..." -NoNewline -ForegroundColor Yellow
    
    $spinChars = @('|', '/', '-', '')
    $steps = [int]($milliseconds / 150)
    for ($i = 0; $i -lt $steps; $i++) {
        $char = $spinChars[$i % 4]
        Write-Host "`b$char" -NoNewline -ForegroundColor Green
        Start-Sleep -Milliseconds 150
    }
    Write-Host "`b Done!" -ForegroundColor Green
}

# 5. UI Printing Functions
function Show-Banner {
    Write-Host "================================================================================" -ForegroundColor DarkCyan
    Write-Host "   █████╗ ██╗     ██╗    ███████╗ █████╗ ██╗  ██╗██╗  ██╗ █████╗ ███████╗" -ForegroundColor Cyan
    Write-Host "  ██╔══██╗██║     ██║    ██╔════╝██╔══██╗██║ ██╔╝██║ ██╔╝██╔══██╗██╔════╝" -ForegroundColor Cyan
    Write-Host "  ███████║██║     ██║    ███████╗███████║█████╔╝ █████╔╝ ███████║█████╗  " -ForegroundColor Cyan
    Write-Host "  ██╔══██║██║     ██║    ╚════██║██╔══██║██╔═██╗ ██╔═██╗ ██╔══██║██╔══╝  " -ForegroundColor Cyan
    Write-Host "  ██║  ██║███████╗██║    ███████║██║  ██║██║  ██╗██║  ██╗██║  ██║██║     " -ForegroundColor Cyan
    Write-Host "  ╚═╝  ╚═╝╚══════╝╚═╝    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     " -ForegroundColor Cyan
    Write-Host "                                                                                " -ForegroundColor Cyan
    Write-Host "                      RAM CLEANER & FLUSHER v1.0                                " -ForegroundColor White
    Write-Host "                 Created By: AliSakkaf (By AliSakkaf)                           " -ForegroundColor White
    Write-Host "        GitHub:   " -NoNewline -ForegroundColor Gray; Write-Host "https://github.com/alisakkaf" -ForegroundColor Cyan
    Write-Host "        Facebook: " -NoNewline -ForegroundColor Gray; Write-Host "https://www.facebook.com/AliSakkaf.Dev/" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor DarkCyan
}

function Show-Dashboard {
    $metrics = Get-MemoryMetrics
    $standby = Get-StandbyMemoryBytes
    
    Write-Host "  CURRENT MEMORY STATUS (Real-time)" -ForegroundColor Magenta
    Write-Host "  ---------------------------------" -ForegroundColor DarkCyan
    
    Write-Host "  [>] Total Physical RAM : " -NoNewline -ForegroundColor White
    Write-Host (Format-MemorySize $metrics.TotalBytes) -ForegroundColor Cyan
    
    Write-Host "  [>] Used Memory        : " -NoNewline -ForegroundColor White
    Write-Host ("{0:N2} GB ({1:N2} MB)" -f $metrics.UsedGB, $metrics.UsedMB) -NoNewline -ForegroundColor Cyan
    
    $load = $metrics.Load
    $barColor = "Green"
    if ($load -ge 85) { $barColor = "Red" }
    elseif ($load -ge 60) { $barColor = "Yellow" }
    
    Write-Host " " -NoNewline
    $bar = Get-ProgressBar $load
    Write-Host $bar -ForegroundColor $barColor
    
    Write-Host "  [>] Free Memory        : " -NoNewline -ForegroundColor White
    Write-Host (Format-MemorySize $metrics.AvailBytes) -ForegroundColor Green
    
    if ($standby -gt 0) {
        Write-Host "  [>] Standby Cache      : " -NoNewline -ForegroundColor White
        Write-Host (Format-MemorySize $standby) -ForegroundColor Yellow
    }
    else {
        Write-Host "  [>] Standby Cache      : " -NoNewline -ForegroundColor White
        Write-Host "Not Available / WMI disabled" -ForegroundColor DarkGray
    }
    Write-Host "================================================================================" -ForegroundColor DarkCyan
}

function Show-OptimizationReport {
    param(
        [PSCustomObject]$before,
        [PSCustomObject]$after
    )
    
    $reclaimedBytes = $before.UsedBytes - $after.UsedBytes
    $reclaimedGB = [Math]::Round($reclaimedBytes / 1GB, 2)
    $reclaimedMB = [Math]::Round($reclaimedBytes / 1MB, 2)
    
    $loadDiff = $before.Load - $after.Load
    
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor DarkCyan
    Write-Host "  OPTIMIZATION REPORT" -ForegroundColor Green
    Write-Host "  -------------------" -ForegroundColor DarkCyan
    
    Write-Host "  [>] Metric      | Before                 | After                  | Reclaimed" -ForegroundColor Yellow
    Write-Host "  ----------------+------------------------+------------------------+---------------------" -ForegroundColor DarkCyan
    
    $beforeUsedStr = "{0:N2} GB ({1:N2} MB)" -f $before.UsedGB, $before.UsedMB
    $afterUsedStr = "{0:N2} GB ({1:N2} MB)" -f $after.UsedGB, $after.UsedMB
    $reclaimedStr = if ($reclaimedBytes -gt 0) { "{0:N2} GB ({1:N2} MB)" -f $reclaimedGB, $reclaimedMB } else { "0.00 GB (0.00 MB)" }
    Write-Host "  Used RAM        | " -NoNewline -ForegroundColor White
    Write-Host $beforeUsedStr.PadRight(23) -NoNewline -ForegroundColor Yellow
    Write-Host "| " -NoNewline -ForegroundColor DarkCyan
    Write-Host $afterUsedStr.PadRight(23) -NoNewline -ForegroundColor Green
    Write-Host "| " -NoNewline -ForegroundColor DarkCyan
    Write-Host $reclaimedStr -ForegroundColor Green
    
    $beforeAvailStr = "{0:N2} GB ({1:N2} MB)" -f $before.AvailGB, $before.AvailMB
    $afterAvailStr = "{0:N2} GB ({1:N2} MB)" -f $after.AvailGB, $after.AvailMB
    $freedStr = if ($reclaimedBytes -gt 0) { "+{0:N2} GB ({1:N2} MB)" -f $reclaimedGB, $reclaimedMB } else { "0.00 GB (0.00 MB)" }
    Write-Host "  Free RAM        | " -NoNewline -ForegroundColor White
    Write-Host $beforeAvailStr.PadRight(23) -NoNewline -ForegroundColor Red
    Write-Host "| " -NoNewline -ForegroundColor DarkCyan
    Write-Host $afterAvailStr.PadRight(23) -NoNewline -ForegroundColor Green
    Write-Host "| " -NoNewline -ForegroundColor DarkCyan
    Write-Host $freedStr -ForegroundColor Green
    
    $beforeLoadStr = "$($before.Load)%"
    $afterLoadStr = "$($after.Load)%"
    $loadDiffStr = if ($loadDiff -gt 0) { "-$($loadDiff)%" } else { "0%" }
    Write-Host "  RAM Load        | " -NoNewline -ForegroundColor White
    Write-Host $beforeLoadStr.PadRight(23) -NoNewline -ForegroundColor Yellow
    Write-Host "| " -NoNewline -ForegroundColor DarkCyan
    Write-Host $afterLoadStr.PadRight(23) -NoNewline -ForegroundColor Green
    Write-Host "| " -NoNewline -ForegroundColor DarkCyan
    Write-Host $loadDiffStr -ForegroundColor Magenta
    
    Write-Host "  ----------------+------------------------+------------------------+---------------------" -ForegroundColor DarkCyan
    
    Write-Host ""
    if ($reclaimedBytes -gt 0) {
        Write-Host "  >>> TOTAL PHYSICAL RAM RELEASED: " -NoNewline -ForegroundColor Green
        Write-Host "$reclaimedGB GB ($reclaimedMB MB) <<<" -ForegroundColor Green
    }
    else {
        Write-Host "  >>> SYSTEM RAM IS ALREADY AT OPTIMAL STATE <<<" -ForegroundColor Cyan
    }
    Write-Host "================================================================================" -ForegroundColor DarkCyan
}

# 6. Optimization Actions
function Trim-ProcessWorkingSets {
    Write-Host "[*] Action: " -NoNewline -ForegroundColor White; Write-Host "Force Emptying Active Process Working Sets..." -ForegroundColor Yellow
    $processes = Get-Process
    $successCount = 0
    $skippedCount = 0
    
    foreach ($proc in $processes) {
        if ($proc.Id -eq $PID) { continue }
        try {
            $handle = $proc.Handle
            if ($handle -ne [IntPtr]::Zero) {
                if ([Win32Memory]::ForceEmpty($handle)) {
                    $successCount++
                }
                else {
                    $skippedCount++
                }
            }
        }
        catch {
            $skippedCount++
        }
    }
    Write-Host "[+] Working sets of $successCount processes successfully trimmed." -ForegroundColor Green
}

function Purge-StandbyList {
    Write-Host "[*] Action: " -NoNewline -ForegroundColor White; Write-Host "Purging Standby Memory Cache Lists..." -ForegroundColor Yellow
    $status = [Win32Memory]::PurgeMemoryList(4) # MemoryPurgeStandbyList
    if ($status -eq 0) {
        Write-Host "[+] Standby List purged successfully." -ForegroundColor Green
    }
    elseif ($status -eq 0xC0000022) {
        Write-Host "[-] Access Denied: SeProfileSingleProcessPrivilege is required." -ForegroundColor Red
    }
    else {
        Write-Host ("[-] Failed to purge Standby List. NTSTATUS: 0x{0:X}" -f $status) -ForegroundColor Red
    }
}

function Flush-ModifiedList {
    Write-Host "[*] Action: " -NoNewline -ForegroundColor White; Write-Host "Flushing Modified Memory Pages to Disk..." -ForegroundColor Yellow
    $status = [Win32Memory]::PurgeMemoryList(3) # MemoryFlushModifiedList
    if ($status -eq 0) {
        Write-Host "[+] Modified Memory pages flushed successfully." -ForegroundColor Green
    }
    else {
        Write-Host ("[-] Failed to flush Modified Memory pages. NTSTATUS: 0x{0:X}" -f $status) -ForegroundColor Red
    }
}

function Trim-SystemWorkingSets {
    Write-Host "[*] Action: " -NoNewline -ForegroundColor White; Write-Host "Trimming System & Driver Working Sets..." -ForegroundColor Yellow
    $status = [Win32Memory]::PurgeMemoryList(2) # MemoryEmptyWorkingSets
    if ($status -eq 0) {
        Write-Host "[+] System Working Sets trimmed successfully." -ForegroundColor Green
    }
    else {
        Write-Host ("[-] Failed to trim System Working Sets. NTSTATUS: 0x{0:X}" -f $status) -ForegroundColor Red
    }
}

# 7. Main Menu Loop
$running = $true
while ($running) {
    Clear-Host
    Show-Banner
    Show-Dashboard
    
    Write-Host "  OPTIMIZATION OPTIONS:" -ForegroundColor Magenta
    Write-MenuOption "1" "Maximum Optimization (Run All Actions Sequentially)"
    Write-MenuOption "2" "Quick Optimization (Trim Process Working Sets)"
    Write-MenuOption "3" "Standby Cache Purge (Release Standby Memory)"
    Write-MenuOption "4" "Modified Memory Flush (Flush Modified Pages to Disk)"
    Write-MenuOption "5" "System-Wide Memory Flush (Trim Kernel & Drivers)"
    Write-MenuOption "6" "Exit Program" "Red"
    Write-Host "================================================================================" -ForegroundColor DarkCyan
    Write-Host ""
    
    $choice = Read-Host "Select an option [1-6]"
    
    switch ($choice) {
        "1" {
            $before = Get-MemoryMetrics
            
            # Run all sequentially
            Flush-ModifiedList
            Purge-StandbyList
            Trim-ProcessWorkingSets
            Trim-SystemWorkingSets
            
            Start-SyncDelay -milliseconds 2000
            $after = Get-MemoryMetrics
            Show-OptimizationReport $before $after
            Read-Host "Press Enter to return to menu..."
        }
        "2" {
            $before = Get-MemoryMetrics
            Trim-ProcessWorkingSets
            Start-SyncDelay
            $after = Get-MemoryMetrics
            Show-OptimizationReport $before $after
            Read-Host "Press Enter to return to menu..."
        }
        "3" {
            $before = Get-MemoryMetrics
            Purge-StandbyList
            Start-SyncDelay
            $after = Get-MemoryMetrics
            Show-OptimizationReport $before $after
            Read-Host "Press Enter to return to menu..."
        }
        "4" {
            $before = Get-MemoryMetrics
            Flush-ModifiedList
            Start-SyncDelay
            $after = Get-MemoryMetrics
            Show-OptimizationReport $before $after
            Read-Host "Press Enter to return to menu..."
        }
        "5" {
            $before = Get-MemoryMetrics
            Trim-SystemWorkingSets
            Start-SyncDelay
            $after = Get-MemoryMetrics
            Show-OptimizationReport $before $after
            Read-Host "Press Enter to return to menu..."
        }
        "6" {
            Write-Host "Thank you for using RAM Cleaner & Flusher. Goodbye!" -ForegroundColor Green
            Start-Sleep -Seconds 1
            $running = $false
        }
        default {
            Write-Host "[!] Invalid selection. Please choose a number between 1 and 6." -ForegroundColor Red
            Start-Sleep -Seconds 1.5
        }
    }
}
