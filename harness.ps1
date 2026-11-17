param(
  [ValidateSet('start','stop','status','open')][string]$Action = 'status',
  [string]$Serial,
  [string]$Adb = 'adb'
)
$ErrorActionPreference = 'Stop'
$deviceBase = '/data/local/dsh-verify-20261117-a1'
if (-not (Get-Command $Adb -ErrorAction SilentlyContinue)) { throw 'ADB not found. Add Platform-Tools to PATH or pass -Adb.' }
if (-not $Serial) {
  $deviceOutput = & $Adb devices
  if ($LASTEXITCODE -ne 0) { throw 'Could not list ADB devices.' }
  $devices = @($deviceOutput | Where-Object { $_ -match '^\S+\s+device$' } | ForEach-Object { ($_ -split '\s+')[0] })
  if ($devices.Count -ne 1) { throw 'Connect exactly one authorized device or pass -Serial.' }
  $Serial = $devices[0]
}
function Invoke-Device([string]$Command) {
  $output = & $Adb -s $Serial shell $Command
  if ($LASTEXITCODE -ne 0) { throw 'ADB command failed.' }
  $output
}
if ($Action -eq 'open') {
  $log = Invoke-Device "su -c 'cat $deviceBase/logs/web.log'"
  $match = [regex]::Match(($log -join "`n"), 'dsh web: (http://127\.0\.0\.1:3080/\?token=[A-Za-z0-9_-]+)')
  if (-not $match.Success) { throw 'No authenticated launch URL found. Start Harness first.' }
  $url = $match.Groups[1].Value
  $launchOutput = Invoke-Device "am start -W -a android.intent.action.VIEW -p com.android.chrome -d '$url'"
  $launchOutput | ForEach-Object { "$_" -replace '\?token=[A-Za-z0-9_-]+', '?token=[redacted]' }
  # A direct browser navigation allows the saved Strict cookie on this device.
  Start-Sleep -Seconds 2
  Invoke-Device 'input keycombination 113 40'
  Invoke-Device 'input text http://127.0.0.1:3080/'
  Invoke-Device 'input keyevent 66'
} else {
  Invoke-Device "su -c '$deviceBase/scripts/service.sh $Action'"
}
