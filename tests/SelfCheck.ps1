# Non-destructive self-checks for WinKit parsers, ID validation, status classifier, presets, and syntax
if ([System.Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA') {
    & powershell.exe -Sta -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath
    exit $LASTEXITCODE
}
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
    Assert-True ($app.Id -match '^[^\s.]+\.[^\s]+$') "Built-in app ID should contain dot: $($app.Id)"
    if ($app.ChocoId) {
        Assert-True (Test-SafePackageId $app.ChocoId) "Built-in ChocoId should be valid: $($app.ChocoId)"
    }
}
Assert-True ((Get-AppPackageId -App $global:apps[0] -Provider 'winget') -eq 'Google.Chrome') 'Get-AppPackageId winget mismatch'
Assert-True ((Get-AppPackageId -App $global:apps[0] -Provider 'choco') -eq 'googlechrome') 'Get-AppPackageId choco mismatch'
Assert-True (-not (Test-SafePackageId 'Foo.Bar & calc.exe')) 'Command injection in ID must be rejected'
Assert-True (-not (Test-SafePackageId 'Foo.Bar" --force')) 'Quote injection in ID must be rejected'
Assert-True (-not (Test-SafePackageId '')) 'Empty ID must be rejected'

# 4. Validate ConvertFrom-WingetTable across English, localized, and footer lines
$enList = @(
    'Name          Id                  Version  Available  Source'
    '------------------------------------------------------------'
    'Git           Git.Git             2.56.1              winget'
    '7-Zip         7zip.7zip           24.08    24.09      winget'
    ''
    '1 upgrades available. Run winget upgrade --all to upgrade.'
)
$parsedEn = @(ConvertFrom-WingetTable -Lines $enList)
Assert-True ($parsedEn.Count -eq 2) 'Expected 2 rows in English table (footer ignored)'
Assert-True ($parsedEn[0].Id -eq 'Git.Git' -and $parsedEn[0].Available -eq '') 'Empty Available must stay empty when Source exists'
Assert-True ($parsedEn[1].Id -eq '7zip.7zip' -and $parsedEn[1].Available -eq '24.09') 'Available version should be parsed'

$ruList = @(
    [regex]::Unescape('\u0418\u043C\u044F           \u0418\u0414                  \u0412\u0435\u0440\u0441\u0438\u044F   \u0414\u043E\u0441\u0442\u0443\u043F\u043D\u043E   \u0418\u0441\u0442\u043E\u0447\u043D\u0438\u043A')
    '--------------------------------------------------------------'
    'Notepad++     Notepad++.Notepad++ 8.9.9    8.9.9.1    winget'
)
$parsedRu = @(ConvertFrom-WingetTable -Lines $ruList)
Assert-True ($parsedRu.Count -eq 1 -and $parsedRu[0].Id -eq 'Notepad++.Notepad++' -and $parsedRu[0].Available -eq '8.9.9.1') 'Localized headers should parse cleanly'

$chocoList = @(
    'Chocolatey v2.4.0'
    'git|2.47.1'
    '7zip|24.08'
    '2 packages installed.'
)
$parsedChoco = @(ConvertFrom-ChocoOutput -Lines $chocoList)
Assert-True ($parsedChoco.Count -eq 2 -and $parsedChoco[0].Id -eq 'git' -and $parsedChoco[1].Version -eq '24.08') 'Chocolatey list -r should parse cleanly'
$parsedChocoOut = @(ConvertFrom-ChocoOutput -Lines @('7zip|24.08|24.09|false') -Outdated)
Assert-True ($parsedChocoOut.Count -eq 1 -and $parsedChocoOut[0].Available -eq '24.09') 'Chocolatey outdated -r should parse available version'

# 5. Validate Get-InstallResultStatus classification
$stCancel = Get-InstallResultStatus -Code -1 -Log '' -Cancelled $true
Assert-True ($stCancel.Text -eq 'Cancelled') 'Cancelled status mismatch'
$stSame = Get-InstallResultStatus -Code -1978335220 -Log 'No available upgrade found'
Assert-True ($stSame.Text -eq 'Already installed (Up to date)') 'Already installed code mismatch'
$stUpd = Get-InstallResultStatus -Code 0 -Log 'Trying to upgrade... Successfully installed'
Assert-True ($stUpd.Text -eq 'Successfully updated') 'Updated status mismatch'
$stPartialFail = Get-InstallResultStatus -Code -1978335212 -Log 'Trying to upgrade... Successfully installed App1... Installer failed for App2'
Assert-True ($stPartialFail.Text -eq 'Installation failed') 'Non-zero exit code must fail even if earlier log line succeeded'
$stChocoSame = Get-InstallResultStatus -Code 0 -Log "git v2.47.0 is already installed.`nChocolatey installed 0/1 packages."
Assert-True ($stChocoSame.Text -eq 'Already installed (Up to date)') 'Chocolatey already installed status mismatch'
$stChocoOk = Get-InstallResultStatus -Code 0 -Log 'Chocolatey installed 1/1 packages.'
Assert-True ($stChocoOk.Text -eq 'Installed successfully') 'Chocolatey install status mismatch'
$stChocoUpd = Get-InstallResultStatus -Code 0 -Log 'Chocolatey upgraded 1/1 packages.'
Assert-True ($stChocoUpd.Text -eq 'Successfully updated') 'Chocolatey upgrade status mismatch'

# 6. Validate JSON & TXT preset round-trip
$tmpJson = Join-Path $env:TEMP "winkit_test_preset_$PID.json"
$tmpTxt = Join-Path $env:TEMP "winkit_test_preset_$PID.txt"
try {
    $jsonOut = ConvertTo-WinKitPresetJson -PackageIds @('Git.Git', 'Mozilla.Thunderbird')
    [System.IO.File]::WriteAllText($tmpJson, $jsonOut, [System.Text.UTF8Encoding]::new($false))
    $loadedJson = @(Import-WinKitPreset -Path $tmpJson)
    Assert-True ($loadedJson.Count -eq 2 -and $loadedJson[0] -eq 'Git.Git' -and $loadedJson[1] -eq 'Mozilla.Thunderbird') 'JSON preset round-trip failed'

    [System.IO.File]::WriteAllText($tmpTxt, "Git.Git`n`n7zip.7zip`n", [System.Text.UTF8Encoding]::new($false))
    $loadedTxt = @(Import-WinKitPreset -Path $tmpTxt)
    Assert-True ($loadedTxt.Count -eq 2 -and $loadedTxt[1] -eq '7zip.7zip') 'TXT preset round-trip failed'
} finally {
    Remove-Item $tmpJson, $tmpTxt -Force -ErrorAction SilentlyContinue
}

# 7. Validate WPF UI initialization, search filtering (including '['), and async search callback wiring
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
$xamlRaw = Get-Content (Join-Path $root 'src\ui\Layout.xaml') -Raw -Encoding UTF8
$global:win = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader([xml]$xamlRaw)))
$testControls = @{
    Win = $global:win; TabCats = $global:win.FindName('TabCats'); BtnSelectAll = $global:win.FindName('BtnSelectAll')
    BtnClearAll = $global:win.FindName('BtnClearAll'); BtnSave = $global:win.FindName('BtnSave'); BtnLoad = $global:win.FindName('BtnLoad')
    BtnInstall = $global:win.FindName('BtnInstall'); BtnTheme = $global:win.FindName('BtnTheme'); BtnDebug = $global:win.FindName('BtnDebug')
    ProgressOverlay = $global:win.FindName('ProgressOverlay'); LblProgressTitle = $global:win.FindName('LblProgressTitle')
    LblProgress = $global:win.FindName('LblProgress'); PbInstall = $global:win.FindName('PbInstall'); TxtLog = $global:win.FindName('TxtLog')
    SummaryScroll = $global:win.FindName('SummaryScroll'); SummaryPanel = $global:win.FindName('SummaryPanel')
    BtnCancelInstall = $global:win.FindName('BtnCancelInstall'); TxtSearch = $global:win.FindName('TxtSearch')
    TxtSearchPlaceholder = $global:win.FindName('TxtSearchPlaceholder'); BtnClearSearch = $global:win.FindName('BtnClearSearch')
    BtnExportLog = $global:win.FindName('BtnExportLog'); SearchResultsView = $global:win.FindName('SearchResultsView')
    SearchResultsWrap = $global:win.FindName('SearchResultsWrap'); LblSearchResultStatus = $global:win.FindName('LblSearchResultStatus')
    BtnBackToCats = $global:win.FindName('BtnBackToCats'); PbSearchLoading = $global:win.FindName('PbSearchLoading')
    BtnUpgradeAll = $global:win.FindName('BtnUpgradeAll'); BtnBackendWinget = $global:win.FindName('BtnBackendWinget')
    BtnBackendChoco = $global:win.FindName('BtnBackendChoco'); LblSearchResultTitle = $global:win.FindName('LblSearchResultTitle')
}
. (Join-Path $root 'src\core\Theme.ps1')
Initialize-UIController $testControls
Assert-True ($testControls.TxtSearchPlaceholder.Text -like '*WinGet*') 'Default search placeholder should mention WinGet'
Assert-True ($testControls.LblSearchResultTitle.Text -eq 'WinGet Search Results') 'Default search title should mention WinGet'
Assert-True ($testControls.BtnBackendWinget.Style -eq $global:win.Resources['PrimaryButton']) 'WinGet button should use PrimaryButton style when active'
Assert-True ($testControls.BtnBackendChoco.Style -eq $global:win.Resources['PillButton']) 'Choco button should use PillButton style when inactive'
$script:pkgProvider = 'choco'
Update-ProviderUI
Assert-True ($testControls.TxtSearchPlaceholder.Text -like '*Chocolatey*') 'Choco search placeholder should mention Chocolatey'
Assert-True ($testControls.LblSearchResultTitle.Text -eq 'Chocolatey Search Results') 'Choco search title should update to Chocolatey'
Assert-True ($testControls.BtnBackendChoco.Style -eq $global:win.Resources['PrimaryButton']) 'Choco button should use PrimaryButton style when active'
Assert-True ($testControls.BtnBackendWinget.Style -eq $global:win.Resources['PillButton']) 'WinGet button should use PillButton style when inactive'
$robloxChk = $script:checkBoxes | Where-Object { $_.Uid -eq 'Roblox' } | Select-Object -First 1
Assert-True (-not $robloxChk.IsEnabled) 'Apps without ChocoId must be disabled in Chocolatey mode'
$script:pkgProvider = 'winget'
Update-ProviderUI
Assert-True ($robloxChk.IsEnabled) 'Apps without ChocoId must re-enable in WinGet mode'

# Verify Show-InstallSummary renders a summary card properly
Show-InstallSummary -InstallResults @(@{ App = @{ Name = 'Chocolatey' }; Code = 0; Cancelled = $false; Log = 'OK' }) -WinControls $testControls -Title 'Chocolatey Setup'
Assert-True ($testControls.SummaryScroll.Visibility -eq 'Visible' -and $testControls.PbInstall.Visibility -eq 'Collapsed' -and $testControls.SummaryPanel.Children.Count -eq 1) 'Summary card must render and hide progress bar'
$testControls.TxtSearch.Text = '[chrome'
$testControls.TxtSearch.Text = ''
Assert-True ($testControls.BtnInstall.Content -eq 'Install') 'Install button count should reset cleanly'
& $script:doOnlineSearch 'notepad'
Assert-True ($testControls.SearchResultsView.Visibility -eq 'Visible') 'Online search should switch to SearchResultsView'
$script:searchSeq++
$global:win.Close()

Write-Output "PASS: $($psFiles.Count) scripts parsed, XAML valid, $($global:apps.Count) catalog IDs, parser, status classifier, presets & UI smoke checks passed."
