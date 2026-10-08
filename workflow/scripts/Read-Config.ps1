#requires -Version 7.2
param([Parameter(Mandatory)][string]$ConfigPath)
$ErrorActionPreference = 'Stop'
try { $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop }
catch { throw "Cannot read valid framework JSON configuration: $ConfigPath. $($_.Exception.Message)" }
function Assert-Keys($object, [string[]]$expected, [string]$location) {
    if ($null -eq $object) { throw "Missing config object: $location" }
    foreach ($key in $object.PSObject.Properties.Name) {
        if ($key -notin $expected) { throw "Unknown setting: $location.$key" }
    }
    foreach ($key in $expected) {
        if ($key -notin $object.PSObject.Properties.Name) { throw "Missing setting: $location.$key" }
    }
}
Assert-Keys $config @('schemaVersion','antigravity','preflight') 'config'
if ($config.schemaVersion -ne 1) { throw 'Unsupported configuration schemaVersion.' }
Assert-Keys $config.antigravity @('model','mode','timeoutSeconds','cliPath') 'antigravity'
Assert-Keys $config.preflight @('runtimeCommands','manifestFiles') 'preflight'
if ($config.antigravity.model -isnot [string] -or $config.antigravity.model -notmatch '^[a-zA-Z0-9._-]+$') { throw 'model must be an explicit model slug.' }
if ($config.antigravity.mode -notin @('plan','accept-edits')) { throw 'mode must be plan or accept-edits.' }
if ($config.antigravity.timeoutSeconds -isnot [long] -and $config.antigravity.timeoutSeconds -isnot [int]) { throw 'timeoutSeconds must be an integer.' }
if ($config.antigravity.timeoutSeconds -lt 10 -or $config.antigravity.timeoutSeconds -gt 3600) { throw 'timeoutSeconds must be between 10 and 3600.' }
if ($config.antigravity.cliPath -isnot [string]) { throw 'cliPath must be a string (empty for automatic discovery).' }
foreach ($key in @('runtimeCommands','manifestFiles')) {
    $entries = $config.preflight.$key
    if ($entries -isnot [array]) { throw "preflight.$key must be an array." }
    foreach ($entry in $entries) {
        if ($entry -isnot [string] -or $entry -notmatch '^[a-zA-Z0-9._-]+$') { throw "Invalid name in preflight.$key." }
    }
}
$config
