#requires -Version 7.2
param([string]$ProjectRoot = (Join-Path $PSScriptRoot '../..'), [ValidateRange(1,65535)][int]$Port = 4317)
$ErrorActionPreference='Stop'
$root=(Resolve-Path -LiteralPath $ProjectRoot).Path
$node=Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1
& $node.Source (Join-Path $PSScriptRoot '../dashboard/server.mjs') --project-root $root --port $Port
if ($LASTEXITCODE -ne 0) { throw "Dashboard exited with code $LASTEXITCODE." }
