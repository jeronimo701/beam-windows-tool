$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$parseTokens = $null
$parseErrors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $projectRoot 'beam-tool.ps1'), [ref]$parseTokens, [ref]$parseErrors)
if ($parseErrors.Count) { throw 'beam-tool.ps1 has syntax errors' }
foreach ($statement in $ast.EndBlock.Statements) {
    if ($statement -is [Management.Automation.Language.FunctionDefinitionAst]) {
        . ([scriptblock]::Create($statement.Extent.Text))
    } elseif ($statement -is [Management.Automation.Language.AssignmentStatementAst] -and $statement.Left.Extent.Text -in @('$BeamPackages', '$SettingBlocks', '$ExtraOptimBlocks')) {
        . ([scriptblock]::Create($statement.Extent.Text))
    }
}
$script:passed = 0
function Assert([bool]$Condition, [string]$Name) {
    if (-not $Condition) { throw "FAIL: $Name" }
    $script:passed++
    Write-Host "PASS: $Name"
}
$script:adbCalls = [Collections.Generic.List[object]]::new()
$script:deviceResponse = @('List of devices attached', 'MOCK_DEVICE device product:mock model:Mock_Beam')
function Invoke-Adb {
    param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
    $script:adbCalls.Add([string[]]$Args)
    if (($Args -join ' ') -eq 'devices -l') { return $script:deviceResponse }
}
function Invoke-Fastboot { throw 'Unexpected fastboot call in isolated tests' }
function Require-Adb {}
function Require-Fastboot {}
function Read-Host { param([string]$Prompt) return 'CANCEL' }
function Backup-BeforeChange { throw 'Unexpected backup during cancellation' }

Assert (($ast.FindAll({param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst]}, $true)).Count -ge 20) 'PowerShell syntax and function discovery'
$parts = @(Split-CommandLine 'adb shell settings put system sample "value with spaces"')
Assert ($parts.Count -eq 7 -and $parts[6] -eq 'value with spaces') 'Double-quoted argument parsing'
$parts = @(Split-CommandLine "settings put global sample 'quoted value'")
Assert ($parts.Count -eq 5 -and $parts[4] -eq 'quoted value') 'Single-quoted argument parsing'
Assert (@(Split-CommandLine '').Count -eq 0) 'Empty input parsing'
foreach ($command in @('adb shell settings put global example 1','settings put system example 1','pm disable-user --user 0 com.example.mock','adb install -r app/example.apk','shell cmd package list packages')) {
    $script:adbCalls.Clear()
    Invoke-UserCommandLine $command
    Assert ($script:adbCalls.Count -eq 1) "Allowed command routing: $command"
}
foreach ($command in @('fastboot erase userdata','shell rm /mock','shell','unsupported example')) {
    $script:adbCalls.Clear(); $blocked = $false
    try { Invoke-UserCommandLine $command } catch { $blocked = $true }
    Assert ($blocked -and $script:adbCalls.Count -eq 0) "Unsupported command rejected: $command"
}
$script:adbCalls.Clear(); Invoke-UserCommandLine ''
Assert ($script:adbCalls.Count -eq 0) 'Empty command is a no-op'
Test-Device | Out-Null
Assert ($true) 'One mocked authorized device accepted'
foreach ($response in @(@('List of devices attached'), @('List of devices attached','MOCK unauthorized'), @('List of devices attached','MOCK1 device','MOCK2 device'))) {
    $script:deviceResponse = $response; $blocked = $false
    try { Test-Device } catch { $blocked = $true }
    Assert $blocked 'Missing, unauthorized or multiple mocked devices rejected'
}
$script:deviceResponse = @('List of devices attached','MOCK device')
$script:adbCalls.Clear()
Factory-Reset-Fastboot
Assert ($script:adbCalls.Count -eq 1 -and ($script:adbCalls[0] -join ' ') -eq 'devices -l') 'Cancelled RESET does not back up, erase or reboot'
$script:adbCalls.Clear()
foreach ($name in $SettingBlocks.Keys) { Apply-SettingBlock $name }
Assert ($script:adbCalls.Count -gt 20 -and @($script:adbCalls | Where-Object { $_[0] -ne 'shell' }).Count -eq 0) 'Settings blocks route only through mocked shell'
$script:adbCalls.Clear()
$commandRoot = Join-Path $projectRoot 'commands'
foreach ($file in Get-ChildItem -LiteralPath $commandRoot -Filter '*.txt' -File) {
    foreach ($line in Get-Content -LiteralPath $file.FullName) {
        $line = $line.Trim()
        if (-not $line -or $line.StartsWith('#') -or $line.StartsWith(';') -or $line.StartsWith('//')) { continue }
        Invoke-UserCommandLine $line
    }
}
Assert ($script:adbCalls.Count -gt 100) 'All bundled TXT command lines parse and route to mocks'
Assert ($BeamPackages.Count -gt 50 -and $ExtraOptimBlocks.Count -ge 5) 'Package and alternate preset tables load'
Write-Host "$script:passed tests passed. No real ADB/Fastboot calls or device writes."
