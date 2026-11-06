
import 'dart:io';
import 'dart:convert';

class SystemInfoService {
  static Future<Map<String, dynamic>> fetch() async {
    if (!Platform.isWindows) {
      throw UnsupportedError('Windows required');
    }

    const script = r'''
$ErrorActionPreference = "SilentlyContinue"

function Get-SafeCim {
    param($ClassName, $Namespace = "root/cimv2")
    try {
        Get-CimInstance -Namespace $Namespace -ClassName $ClassName -ErrorAction Stop
    } catch {
        $null
    }
}

$computer = Get-SafeCim "Win32_ComputerSystem"
$processor = Get-SafeCim "Win32_Processor" | Select-Object -First 1
$bios = Get-SafeCim "Win32_BIOS"
$ram = @(Get-SafeCim "Win32_PhysicalMemory")
$disks = @(Get-SafeCim "Win32_DiskDrive")
$battery = Get-SafeCim "Win32_Battery"

$wifi = $false
try {
    $wifi = @(Get-NetAdapter -Physical -ErrorAction Stop |
        Where-Object { $_.InterfaceDescription -match 'Wi-Fi|Wireless|802.11' }).Count -gt 0
} catch {}

$bluetooth = $false
try {
    $bluetooth = @(Get-PnpDevice -Class Bluetooth -ErrorAction Stop |
        Where-Object { $_.Status -eq 'OK' }).Count -gt 0
} catch {}

$static = Get-SafeCim "BatteryStaticData" "root/wmi" |
    Select-Object -First 1

$full = Get-SafeCim "BatteryFullChargedCapacity" "root/wmi" |
    Select-Object -First 1

$ramBytes = ($ram | Measure-Object -Property Capacity -Sum).Sum
$diskBytes = ($disks | Measure-Object -Property Size -Sum).Sum

$health = $null
if ($static.DesignedCapacity -gt 0 -and
    $full.FullChargedCapacity -gt 0) {
    $health = [math]::Round(
        ($full.FullChargedCapacity / $static.DesignedCapacity) * 100, 1
    )
}

$result = [ordered]@{
    brand = $computer.Manufacturer
    model = $computer.Model
    serial = $bios.SerialNumber
    processorActual = $processor.Name

    ramGB = if ($ramBytes) {
        [math]::Round($ramBytes / 1GB, 1)
    } else { $null }

    storageGB = if ($diskBytes) {
        [math]::Round($diskBytes / 1GB, 1)
    } else { $null }

    wifi = $wifi
    bluetooth = $bluetooth

    batteryPercentage = if ($battery) {
        $battery.EstimatedChargeRemaining
    } else { $null }

    designCapacity = $static.DesignedCapacity
    fullChargeCapacity = $full.FullChargedCapacity
    batteryHealth = $health
}

$result | ConvertTo-Json -Compress -Depth 4
''';

    final result = await Process.run(
      'powershell.exe',
      [
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-ExecutionPolicy',
        'Bypass',
        '-Command',
        script,
      ],
      runInShell: false,
    );

    final output = result.stdout.toString()
        .replaceFirst('\uFEFF', '')
        .trim();

    if (result.exitCode != 0) {
      throw Exception(
        'PowerShell error: ${result.stderr}\n${result.stdout}',
      );
    }

    if (output.isEmpty) {
      throw Exception(
        'Windows returned no hardware information: ${result.stderr}',
      );
    }

    final decoded = jsonDecode(output);

    if (decoded is! Map) {
      throw Exception('Invalid hardware information received');
    }

    return Map<String, dynamic>.from(decoded);
  }
}
