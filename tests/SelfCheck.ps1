# Non-destructive self-checks for WinKit parsers, ID validation, and syntax
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

function Assert-True([bool]$Cond, [string]$Msg) {
    if (-not $Cond) { throw "Assertion failed: $Msg" }
}

# 1. Syntax check all PowerShell scripts and XAML
$psFiles = Get-ChildItem -Path $root -Include *.ps1 -Recurse
foreach ($f in $psFiles) {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$null, [ref]$errors) | Out-Null
    Assert-True ($errors.Count -eq 0) "Syntax error in $($f.Name)"
}
[xml](Get-Content (Join-Path $root 'src\ui\Layout.xaml') -Raw -Encoding UTF8) | Out-Null

# 2. Load modules under test
. (Join-Path $root 'src\config\Apps.ps1')
. (Join-Path $root 'src\core\Installer.ps1')
. (Join-Path $root 'src\ui\Controller.ps1')

# 3. Validate built-in catalog IDs and Test-SafePackageId
foreach ($app in $global:apps) {
    Assert-True (Test-SafePackageId $app.Id) "Built-in app ID should be valid: $($app.Id)"
}
Assert-True (-not (Test-SafePackageId 'Foo.Bar & calc.exe')) 'Command injection in ID must be rejected'
Assert-True (-not (Test-SafePackageId 'Foo.Bar" --force')) 'Quote injection in ID must be rejected'
Assert-True (-not (Test-SafePackageId '')) 'Empty ID must be rejected'

# 4. Validate ConvertFrom-WingetTable across English, localized, and Source-column tables
$enList = @(
    'Name          Id                  Version  Available  Source'
    '------------------------------------------------------------'
    'Git           Git.Git             2.56.1              winget'
    '7-Zip         7zip.7zip           24.08    24.09      winget'
)
$parsedEn = @(ConvertFrom-WingetTable -Lines $enList)
Assert-True ($parsedEn.Count -eq 2) 'Expected 2 rows in English table'
Assert-True ($parsedEn[0].Id -eq 'Git.Git' -and $parsedEn[0].Available -eq '') 'Empty Available must stay empty when Source exists'
Assert-True ($parsedEn[1].Id -eq '7zip.7zip' -and $parsedEn[1].Available -eq '24.09') 'Available version should be parsed'

$ruList = @(
    [regex]::Unescape('\u0418\u043C\u044F           \u0418\u0414                  \u0412\u0435\u0440\u0441\u0438\u044F   \u0414\u043E\u0441\u0442\u0443\u043F\u043D\u043E   \u0418\u0441\u0442\u043E\u0447\u043D\u0438\u043A')
    '--------------------------------------------------------------'
    'Notepad++     Notepad++.Notepad++ 8.9.9    8.9.9.1    winget'
)
$parsedRu = @(ConvertFrom-WingetTable -Lines $ruList)
Assert-True ($parsedRu.Count -eq 1 -and $parsedRu[0].Id -eq 'Notepad++.Notepad++' -and $parsedRu[0].Available -eq '8.9.9.1') 'Localized headers should parse cleanly'

Write-Output "PASS: $($psFiles.Count) scripts parsed, XAML valid, $($global:apps.Count) catalog IDs & table parser checks passed."
