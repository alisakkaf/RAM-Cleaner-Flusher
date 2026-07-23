# =========================================================================
#          RAM CLEANER & FLUSHER v1.1 (Pro Edition + CLI & Booster)
# =========================================================================
# Created & Developed By: AliSakkaf (By AliSakkaf)
# GitHub:   https://github.com/alisakkaf
# Facebook: https://www.facebook.com/AliSakkaf.Dev/
# =========================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Max", "Quick", "Standby", "Modified", "System", "Auto")]
    [string]$Mode,

    [Parameter(Mandatory=$false)]
    [switch]$Silent,

    [Parameter(Mandatory=$false)]
    [string[]]$ExcludeProcess = @(),

    [Parameter(Mandatory=$false)]
    [int]$AutoThreshold = 0,

    [Parameter(Mandatory=$false)]
    [string]$BoostApp = ""
)

# Ensure console supports Unicode block characters
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

if (-not $Silent) {
    Clear-Host
}

# Reconstruct passed arguments for elevation forwarding
$passedArgs = ""
if ($Mode) { $passedArgs += " -Mode $Mode" }
if ($Silent) { $passedArgs += " -Silent" }
if ($AutoThreshold -gt 0) { $passedArgs += " -AutoThreshold $AutoThreshold" }
if ($BoostApp) { $passedArgs += " -BoostApp `"$BoostApp`"" }
if ($ExcludeProcess.Count -gt 0) {
    $exList = ($ExcludeProcess | ForEach-Object { "`"$_`"" }) -join ","
    $passedArgs += " -ExcludeProcess $exList"
}

# 1. Admin Privileges Elevation Check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    if (-not $Silent) {
        Write-Host "================================================================================" -ForegroundColor Red
        Write-Host "   [!] ADMINISTRATIVE PRIVILEGES REQUIRED" -ForegroundColor Red
        Write-Host "   This optimizer needs administrative privileges to clean system memory lists." -ForegroundColor White
        Write-Host "   Attempting to restart with Administrator permissions..." -ForegroundColor Yellow
        Write-Host "================================================================================" -ForegroundColor Red
    }
    try {
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"$passedArgs" -Verb RunAs
    }
    catch {
        if (-not $Silent) {
            Write-Host "[-] Elevation failed. Please run this script as Administrator manually." -ForegroundColor Red
            Read-Host "Press Enter to exit..."
        }
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
        if (-not $Silent) {
            Write-Host "[-] Critical Error: Failed to compile Win32 Core Wrappers." -ForegroundColor Red
            Write-Host $_.Exception.Message -ForegroundColor Yellow
            Read-Host "Press Enter to exit..."
        }
        Exit
    }
}

# Enable required privileges
[Win32Memory]::EnableRequiredPrivileges() | Out-Null

# Initialize Global Exclusion List for Interactive & CLI sessions
$script:GlobalExclusions = [System.Collections.Generic.List[string]]::new()
if ($ExcludeProcess -and $ExcludeProcess.Count -gt 0) {
    foreach ($ex in $ExcludeProcess) {
        $cleanEx = $ex.Trim()
        if ($cleanEx -and -not $script:GlobalExclusions.Contains($cleanEx)) {
            $script:GlobalExclusions.Add($cleanEx)
        }
    }
}

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
    param([double]$bytes)
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
            $core = 0; $normal = 0; $reserve = 0
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
    param([int]$percentage)
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
    if ($Silent) { return }
    Write-Host ""
    Write-Host "[*] Status: " -NoNewline -ForegroundColor White
    Write-Host "Waiting for Windows Memory Manager to synchronize..." -NoNewline -ForegroundColor Yellow
    
    $spinChars = @('|', '/', '-', '\')
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
    if ($Silent) { return }
    Write-Host "================================================================================" -ForegroundColor DarkCyan
    Write-Host "   █████╗ ██╗     ██╗    ███████╗ █████╗ ██╗  ██╗██╗  ██╗ █████╗ ███████╗" -ForegroundColor Cyan
    Write-Host "  ██╔══██╗██║     ██║    ██╔════╝██╔══██╗██║ ██╔╝██║ ██╔╝██╔══██╗██╔════╝" -ForegroundColor Cyan
    Write-Host "  ███████║██║     ██║    ███████╗███████║█████╔╝ █████╔╝ ███████║█████╗  " -ForegroundColor Cyan
    Write-Host "  ██╔══██║██║     ██║    ╚════██║██╔══██║██╔═██╗ ██╔═██╗ ██╔══██║██╔══╝  " -ForegroundColor Cyan
    Write-Host "  ██║  ██║███████╗██║    ███████║██║  ██║██║  ██╗██║  ██╗██║  ██║██║     " -ForegroundColor Cyan
    Write-Host "  ╚═╝  ╚═╝╚══════╝╚═╝    ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     " -ForegroundColor Cyan
    Write-Host "                                                                                " -ForegroundColor Cyan
    Write-Host "                      RAM CLEANER & FLUSHER v1.1                                " -ForegroundColor White
    Write-Host "                 Created By: AliSakkaf (By AliSakkaf)                           " -ForegroundColor White
    Write-Host "        GitHub:   " -NoNewline -ForegroundColor Gray; Write-Host "https://github.com/alisakkaf" -ForegroundColor Cyan
    Write-Host "        Facebook: " -NoNewline -ForegroundColor Gray; Write-Host "https://www.facebook.com/AliSakkaf.Dev/" -ForegroundColor Cyan
    if ($script:GlobalExclusions.Count -gt 0) {
        $exStr = ($script:GlobalExclusions -join ", ")
        if ($exStr.Length -gt 50) { $exStr = $exStr.Substring(0, 47) + "..." }
        Write-Host "  [>] Protected Exclusions: " -NoNewline -ForegroundColor White
        Write-Host "$exStr ($($script:GlobalExclusions.Count) active)" -ForegroundColor Cyan
    }
    Write-Host "================================================================================" -ForegroundColor DarkCyan
}

function Show-Dashboard {
    if ($Silent) { return }
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
    if ($script:GlobalExclusions.Count -gt 0) {
        $exStr = ($script:GlobalExclusions -join ", ")
        if ($exStr.Length -gt 50) { $exStr = $exStr.Substring(0, 47) + "..." }
        Write-Host "  [>] Protected Exclusions: " -NoNewline -ForegroundColor White
        Write-Host "$exStr ($($script:GlobalExclusions.Count) active)" -ForegroundColor Cyan
    }
    Write-Host "================================================================================" -ForegroundColor DarkCyan
}

function Show-OptimizationReport {
    param(
        [PSCustomObject]$before,
        [PSCustomObject]$after
    )
    if ($Silent) { return }
    
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
    if ($script:GlobalExclusions.Count -gt 0) {
        $exStr = ($script:GlobalExclusions -join ", ")
        if ($exStr.Length -gt 50) { $exStr = $exStr.Substring(0, 47) + "..." }
        Write-Host "  [>] Protected Exclusions: " -NoNewline -ForegroundColor White
        Write-Host "$exStr ($($script:GlobalExclusions.Count) active)" -ForegroundColor Cyan
    }
    Write-Host "================================================================================" -ForegroundColor DarkCyan
}

# 6. Optimization Actions
function Trim-ProcessWorkingSets {
    param([string[]]$Exclusions = @())
    if (-not $Exclusions -or $Exclusions.Count -eq 0) {
        $Exclusions = $script:GlobalExclusions.ToArray()
    }
    if (-not $Silent) {
        Write-Host "[*] Action: " -NoNewline -ForegroundColor White; Write-Host "Force Emptying Active Process Working Sets..." -ForegroundColor Yellow
    }
    $processes = Get-Process
    $successCount = 0
    $skippedCount = 0
    $excludedCount = 0
    
    foreach ($proc in $processes) {
        if ($proc.Id -eq $PID) { continue }
        if ($Exclusions -and $Exclusions.Count -gt 0) {
            $pName = $proc.ProcessName
            if ($Exclusions -contains $pName -or $Exclusions -contains "$pName.exe") {
                $excludedCount++
                continue
            }
        }
        try {
            $handle = $proc.Handle
            if ($handle -ne [IntPtr]::Zero) {
                if ([Win32Memory]::ForceEmpty($handle)) {
                    $successCount++
                } else {
                    $skippedCount++
                }
            }
        } catch {
            $skippedCount++
        }
    }
    if (-not $Silent) {
        Write-Host "[+] Working sets of $successCount processes successfully trimmed." -ForegroundColor Green
        if ($excludedCount -gt 0) {
            Write-Host "[!] $excludedCount processes were protected by exclusion list." -ForegroundColor Cyan
        }
    }
}

function Purge-StandbyList {
    if (-not $Silent) {
        Write-Host "[*] Action: " -NoNewline -ForegroundColor White; Write-Host "Purging Standby Memory Cache Lists..." -ForegroundColor Yellow
    }
    $status = [Win32Memory]::PurgeMemoryList(4) # MemoryPurgeStandbyList
    if ($status -eq 0) {
        if (-not $Silent) { Write-Host "[+] Standby List purged successfully." -ForegroundColor Green }
    } elseif ($status -eq 0xC0000022) {
        if (-not $Silent) { Write-Host "[-] Access Denied: SeProfileSingleProcessPrivilege is required." -ForegroundColor Red }
    } else {
        if (-not $Silent) { Write-Host ("[-] Failed to purge Standby List. NTSTATUS: 0x{0:X}" -f $status) -ForegroundColor Red }
    }
}

function Flush-ModifiedList {
    if (-not $Silent) {
        Write-Host "[*] Action: " -NoNewline -ForegroundColor White; Write-Host "Flushing Modified Memory Pages to Disk..." -ForegroundColor Yellow
    }
    $status = [Win32Memory]::PurgeMemoryList(3) # MemoryFlushModifiedList
    if ($status -eq 0) {
        if (-not $Silent) { Write-Host "[+] Modified Memory pages flushed successfully." -ForegroundColor Green }
    } else {
        if (-not $Silent) { Write-Host ("[-] Failed to flush Modified Memory pages. NTSTATUS: 0x{0:X}" -f $status) -ForegroundColor Red }
    }
}

function Trim-SystemWorkingSets {
    if (-not $Silent) {
        Write-Host "[*] Action: " -NoNewline -ForegroundColor White; Write-Host "Trimming System & Driver Working Sets..." -ForegroundColor Yellow
    }
    $status = [Win32Memory]::PurgeMemoryList(2) # MemoryEmptyWorkingSets
    if ($status -eq 0) {
        if (-not $Silent) { Write-Host "[+] System Working Sets trimmed successfully." -ForegroundColor Green }
    } else {
        if (-not $Silent) { Write-Host ("[-] Failed to trim System Working Sets. NTSTATUS: 0x{0:X}" -f $status) -ForegroundColor Red }
    }
}

function Start-AppBoost {
    param(
        [string]$AppPath,
        [string[]]$Exclusions = @()
    )
    if (-not $Silent) {
        Write-Host "[*] App Launch Booster: Preparing system memory for launch..." -ForegroundColor Yellow
    }
    Flush-ModifiedList
    Purge-StandbyList
    Trim-ProcessWorkingSets -Exclusions $Exclusions
    Trim-SystemWorkingSets
    
    if (-not $Silent) {
        Write-Host "[*] Launching '$AppPath' with High Priority Class..." -ForegroundColor Green
    }
    try {
        $p = Start-Process -FilePath $AppPath -PassThru
        if ($null -ne $p) {
            $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
            if (-not $Silent) {
                Write-Host "[+] Application launched successfully with HIGH priority! PID: $($p.Id)" -ForegroundColor Green
            }
        }
    } catch {
        if (-not $Silent) {
            Write-Host "[-] Failed to launch application or set high priority: $_" -ForegroundColor Red
        }
    }
}

# 7. Non-Interactive CLI Mode Execution
if ($Mode -or $AutoThreshold -gt 0 -or $BoostApp) {
    # Check AutoThreshold requirement
    if ($AutoThreshold -gt 0) {
        $currentMetrics = Get-MemoryMetrics
        if ($currentMetrics.Load -lt $AutoThreshold) {
            if (-not $Silent) {
                Write-Host "[*] Current RAM load ($($currentMetrics.Load)%) is below auto-threshold ($AutoThreshold%). Skipping optimization." -ForegroundColor Cyan
            }
            Exit
        }
    }

    if ($BoostApp) {
        Start-AppBoost -AppPath $BoostApp -Exclusions $ExcludeProcess
        Exit
    }

    $before = Get-MemoryMetrics
    switch ($Mode) {
        "Max" {
            Flush-ModifiedList
            Purge-StandbyList
            Trim-ProcessWorkingSets -Exclusions $ExcludeProcess
            Trim-SystemWorkingSets
        }
        "Quick" {
            Trim-ProcessWorkingSets -Exclusions $ExcludeProcess
        }
        "Standby" {
            Purge-StandbyList
        }
        "Modified" {
            Flush-ModifiedList
        }
        "System" {
            Trim-SystemWorkingSets
        }
        default {
            Flush-ModifiedList
            Purge-StandbyList
            Trim-ProcessWorkingSets -Exclusions $ExcludeProcess
            Trim-SystemWorkingSets
        }
    }

    Start-SyncDelay -milliseconds 1500
    $after = Get-MemoryMetrics
    Show-OptimizationReport $before $after
    Exit
}

# 8. Interactive Main Menu Loop
$running = $true
while ($running) {
    Clear-Host
    Show-Banner
    Show-Dashboard
    
    Write-Host "  OPTIMIZATION & FEATURE OPTIONS:" -ForegroundColor Magenta
    Write-MenuOption "1" "Maximum Optimization (Run All Actions Sequentially)"
    Write-MenuOption "2" "Quick Optimization (Trim Process Working Sets)"
    Write-MenuOption "3" "Standby Cache Purge (Release Standby Memory)"
    Write-MenuOption "4" "Modified Memory Flush (Flush Modified Pages to Disk)"
    Write-MenuOption "5" "System-Wide Memory Flush (Trim Kernel & Drivers)"
    Write-MenuOption "6" "App Launch Booster (Pre-Purge RAM & Launch App with HIGH Priority)" "Yellow"
    Write-MenuOption "7" "Exclusion Protection Manager (Manage Protected Applications)" "Yellow"
    Write-MenuOption "8" "Auto Memory Threshold Check (Run Optimization if RAM > Threshold %)" "Yellow"
    Write-MenuOption "9" "Exit Program" "Red"
    Write-Host "================================================================================" -ForegroundColor DarkCyan
    Write-Host ""
    
    $choice = Read-Host "Select an option [1-9]"
    
    switch ($choice) {
        "1" {
            $before = Get-MemoryMetrics
            Flush-ModifiedList
            Purge-StandbyList
            Trim-ProcessWorkingSets -Exclusions $script:GlobalExclusions.ToArray()
            Trim-SystemWorkingSets
            Start-SyncDelay -milliseconds 2000
            $after = Get-MemoryMetrics
            Show-OptimizationReport $before $after
            Read-Host "Press Enter to return to menu..."
        }
        "2" {
            $before = Get-MemoryMetrics
            Trim-ProcessWorkingSets -Exclusions $script:GlobalExclusions.ToArray()
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
            Write-Host ""
            Write-Host "=== APP LAUNCH BOOSTER ===" -ForegroundColor Yellow
            $appInput = Read-Host "Enter full executable path to launch (e.g. C:\Games\game.exe)"
            if ($appInput -and (Test-Path $appInput)) {
                $purgeChoice = Read-Host "Purge RAM before launch? [Y/n]"
                if ($purgeChoice -notmatch '^[Nn]') {
                    Start-AppBoost -AppPath $appInput -Exclusions $script:GlobalExclusions.ToArray()
                } else {
                    Write-Host "[*] Launching '$appInput' with High Priority Class..." -ForegroundColor Green
                    try {
                        $p = Start-Process -FilePath $appInput -PassThru
                        if ($null -ne $p) {
                            $p.PriorityClass = [System.Diagnostics.ProcessPriorityClass]::High
                            Write-Host "[+] Launched successfully with HIGH priority! PID: $($p.Id)" -ForegroundColor Green
                        }
                    } catch {
                        Write-Host "[-] Failed to launch application: $_" -ForegroundColor Red
                    }
                }
            } else {
                Write-Host "[-] Error: Executable file path not found or empty." -ForegroundColor Red
            }
            Read-Host "Press Enter to return to menu..."
        }
        "7" {
            $exLoop = $true
            while ($exLoop) {
                Clear-Host
                Show-Banner
                Write-Host "=== EXCLUSION PROTECTION MANAGER ===" -ForegroundColor Yellow
                Write-Host "Currently Protected Applications:" -ForegroundColor White
                if ($script:GlobalExclusions.Count -eq 0) {
                    Write-Host "  (No applications excluded)" -ForegroundColor DarkGray
                } else {
                    foreach ($item in $script:GlobalExclusions) {
                        Write-Host "  - $item" -ForegroundColor Cyan
                    }
                }
                Write-Host "------------------------------------" -ForegroundColor DarkCyan
                Write-Host "  [A] Add Process Name (e.g. chrome, devenv, vlc.exe)" -ForegroundColor White
                Write-Host "  [C] Clear Exclusion List" -ForegroundColor White
                Write-Host "  [B] Back to Main Menu" -ForegroundColor Yellow
                Write-Host "------------------------------------" -ForegroundColor DarkCyan
                $exChoice = Read-Host "Select action [A/C/B]"
                switch ($exChoice.ToUpper()) {
                    "A" {
                        $newEx = Read-Host "Enter process name to exclude (e.g. devenv)"
                        if ($newEx) {
                            $cleanNew = $newEx.Trim()
                            if (-not $script:GlobalExclusions.Contains($cleanNew)) {
                                $script:GlobalExclusions.Add($cleanNew)
                                Write-Host "[+] Added '$cleanNew' to protection list." -ForegroundColor Green
                                Start-Sleep -Seconds 1
                            }
                        }
                    }
                    "C" {
                        $script:GlobalExclusions.Clear()
                        Write-Host "[+] Exclusion protection list cleared." -ForegroundColor Yellow
                        Start-Sleep -Seconds 1
                    }
                    "B" { $exLoop = $false }
                }
            }
        }
        "8" {
            Write-Host ""
            Write-Host "=== AUTOMATIC MEMORY THRESHOLD OPTIMIZER ===" -ForegroundColor Yellow
            $threshInput = Read-Host "Enter RAM Load trigger percentage (e.g. 80 for 80% RAM load)"
            $threshVal = 0
            if ([int]::TryParse($threshInput, [ref]$threshVal) -and $threshVal -gt 0 -and $threshVal -le 100) {
                $cur = Get-MemoryMetrics
                Write-Host "[*] Current RAM Load: $($cur.Load)% | Trigger Threshold: $threshVal%" -ForegroundColor White
                if ($cur.Load -ge $threshVal) {
                    Write-Host "[!] Current RAM load exceeds threshold! Starting Maximum Optimization..." -ForegroundColor Yellow
                    $before = Get-MemoryMetrics
                    Flush-ModifiedList
                    Purge-StandbyList
                    Trim-ProcessWorkingSets -Exclusions $script:GlobalExclusions.ToArray()
                    Trim-SystemWorkingSets
                    Start-SyncDelay -milliseconds 2000
                    $after = Get-MemoryMetrics
                    Show-OptimizationReport $before $after
                } else {
                    Write-Host "[+] System RAM load ($($cur.Load)%) is below threshold ($threshVal%). Memory state is optimal." -ForegroundColor Green
                }
            } else {
                Write-Host "[-] Invalid threshold value entered. Please enter a number between 1 and 100." -ForegroundColor Red
            }
            Read-Host "Press Enter to return to menu..."
        }
        "9" {
            Write-Host "Thank you for using RAM Cleaner & Flusher. Goodbye!" -ForegroundColor Green
            Start-Sleep -Seconds 1
            $running = $false
        }
        default {
            Write-Host "[!] Invalid selection. Please choose a number between 1 and 9." -ForegroundColor Red
            Start-Sleep -Seconds 1.5
        }
    }
}