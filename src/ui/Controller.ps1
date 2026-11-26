# --- WinKit UI Controller & Event Handlers ---

function Invoke-DoEvents {
    $frame = New-Object System.Windows.Threading.DispatcherFrame
    [System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [System.Action]({ $frame.Continue = $false })
    ) | Out-Null
    [System.Windows.Threading.Dispatcher]::PushFrame($frame)
}

function ConvertFrom-WingetTable {
    param([string[]]$Lines)

    $results = @()
    if (-not $Lines -or $Lines.Count -lt 3) { return $results }

    $dashIdx = -1
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^-{10,}') {
            $dashIdx = $i
            break
        }
    }
    if ($dashIdx -lt 1) { return $results }

    $header = $Lines[$dashIdx - 1]
    $cols = [regex]::Matches($header, '\S+')
    if ($cols.Count -lt 3) { return $results }

    $idCol = $cols[1].Index
    $verCol = $cols[2].Index
    $availCol = -1
    $availEnd = -1
    if ($cols.Count -ge 4 -and $cols[3].Value -notmatch '^(?i)(Source|Match|\u0418\u0441\u0442\u043E\u0447\u043D\u0438\u043A|\u0421\u043E\u0432\u043F\u0430\u0434\u0435\u043D\u0438\u0435|Quelle|Origen)$') {
        $availCol = $cols[3].Index
        if ($cols.Count -ge 5) { $availEnd = $cols[4].Index }
    }

    $seenData = $false
    for ($i = $dashIdx + 1; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) {
            if ($seenData) { break }
            continue
        }
        if ($line.Length -le $idCol) { continue }

        $name = $line.Substring(0, [Math]::Min($line.Length, $idCol)).Trim()
        $id = ($line.Substring($idCol) -split '\s+')[0]
        if (-not ($id -match '^[a-zA-Z0-9._+\-]+\.[a-zA-Z0-9._+\-]+$')) { continue }

        $verEnd = if ($availCol -gt $verCol) { $availCol } else { -1 }
        $version = if ($line.Length -gt $verCol) {
            $slice = if ($verEnd -gt $verCol -and $line.Length -gt $verEnd) { $line.Substring($verCol, $verEnd - $verCol) } else { $line.Substring($verCol) }
            ($slice.Trim() -split '\s+')[0]
        } else { "" }
        $avail = if ($availCol -gt 0 -and $line.Length -gt $availCol) {
            $slice = if ($availEnd -gt $availCol -and $line.Length -gt $availEnd) { $line.Substring($availCol, $availEnd - $availCol) } else { $line.Substring($availCol) }
            ($slice.Trim() -split '\s+')[0]
        } else { "" }

        if ($name -and $id) {
            $seenData = $true
            $results += [PSCustomObject]@{
                Name      = $name
                Id        = $id
                Version   = $version
                Available = $avail
            }
        }
    }
    return $results
}

function ConvertFrom-ChocoLines {
    param([string[]]$Lines, [switch]$Outdated)

    $results = @()
    if (-not $Lines) { return $results }
    foreach ($line in $Lines) {
        $t = $line.Trim()
        if (-not $t -or $t -notmatch '\|') { continue }
        $parts = $t -split '\|'
        if ($parts.Count -lt 2) { continue }
        $id = $parts[0].Trim()
        if (-not (Test-SafePackageId $id)) { continue }
        if ($Outdated -and $parts.Count -ge 3) {
            $results += [PSCustomObject]@{ Name = $id; Id = $id; Version = $parts[1].Trim(); Available = $parts[2].Trim() }
        } else {
            $results += [PSCustomObject]@{ Name = $id; Id = $id; Version = $parts[1].Trim(); Available = "" }
        }
    }
    return $results
}

function ConvertTo-WinKitPresetJson {
    param([string[]]$PackageIds)

    $pkgList = @()
    foreach ($id in $PackageIds) {
        if ($id) { $pkgList += @{ PackageIdentifier = $id } }
    }
    $exportObj = [ordered]@{
        '$schema'     = "https://aka.ms/winget-packages.schema.2.0.json"
        CreationDate = (Get-Date -Format "yyyy-MM-ddTHH:mm:ssK")
        Sources      = @(
            [ordered]@{
                Packages      = $pkgList
                SourceDetails = [ordered]@{
                    Argument   = "https://cdn.winget.microsoft.com/cache"
                    Identifier = "Microsoft.Winget.Source_8wekyb3d8bbwe"
                    Name       = "winget"
                    Type       = "Microsoft.PreIndexed.Package"
                }
            }
        )
    }
    return ($exportObj | ConvertTo-Json -Depth 5)
}

function Import-WinKitPresetIds {
    param([string]$Path)

    if ($Path.EndsWith(".json", [System.StringComparison]::OrdinalIgnoreCase)) {
        $ids = @()
        $jsonContent = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($jsonContent.Sources) {
            foreach ($src in $jsonContent.Sources) {
                if ($src.Packages) {
                    foreach ($pkg in $src.Packages) {
                        if ($pkg.PackageIdentifier) { $ids += [string]$pkg.PackageIdentifier }
                    }
                }
            }
        }
        return $ids
    }
    return @(Get-Content $Path -Encoding UTF8 | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Initialize-UIController($winControls) {
    $script:winControls = $winControls
    $script:win = $winControls.Win
    $script:tabCats = $winControls.TabCats
    $script:btnSelectAll = $winControls.BtnSelectAll
    $script:btnClearAll = $winControls.BtnClearAll
    $script:btnUpgradeAll = $winControls.BtnUpgradeAll
    $script:btnSave = $winControls.BtnSave
    $script:btnLoad = $winControls.BtnLoad
    $script:btnInstall = $winControls.BtnInstall
    $script:btnCancelInstall = $winControls.BtnCancelInstall
    $script:btnTheme = $winControls.BtnTheme
    $script:btnDebug = $winControls.BtnDebug
    $script:ProgressOverlay = $winControls.ProgressOverlay
    $script:TxtLog = $winControls.TxtLog
    $script:SummaryScroll = $winControls.SummaryScroll
    $script:SummaryPanel = $winControls.SummaryPanel
    $script:txtSearch = $winControls.TxtSearch
    $script:txtSearchPlaceholder = $winControls.TxtSearchPlaceholder
    $script:btnClearSearch = $winControls.BtnClearSearch
    $script:btnExportLog = $winControls.BtnExportLog
    $script:searchResultsView = $winControls.SearchResultsView
    $script:searchResultsWrap = $winControls.SearchResultsWrap
    $script:lblSearchResultStatus = $winControls.LblSearchResultStatus
    $script:btnBackToCats = $winControls.BtnBackToCats
    $script:pbSearchLoading = $winControls.PbSearchLoading
    $script:btnBackendWinget = $winControls.BtnBackendWinget
    $script:btnBackendChoco = $winControls.BtnBackendChoco
    $script:lblSearchResultTitle = $winControls.LblSearchResultTitle

    $script:pkgProvider = "winget"
    $script:isConsoleVisible = $false
    $script:checkBoxes = @()
    $script:onlineCheckBoxes = @()
    $script:appPanels = @()
    $script:registeredApps = @{}
    $script:appStatusLabels = @{}
    $script:installedPackages = @{}
    $script:searchSeq = 0
    $global:depCheckBoxes = @{}

    function script:Get-SelectedApps {
        $selected = @()
        $seenIds = @{}
        foreach ($chk in ($script:checkBoxes + $script:onlineCheckBoxes)) {
            if ($chk.IsChecked -eq $true -and $script:registeredApps.ContainsKey($chk.Uid)) {
                $app = $script:registeredApps[$chk.Uid]
                $prov = if ($app.Provider) { $app.Provider } else { $script:pkgProvider }
                $pkgId = Get-AppPackageId -App $app -Provider $prov
                if ($pkgId -and -not $seenIds.ContainsKey($pkgId)) {
                    $seenIds[$pkgId] = $true
                    $selected += $app
                }
            }
        }
        return $selected
    }

    function script:Update-InstallCount {
        $count = @(Get-SelectedApps).Count
        if ($count -gt 0) {
            $script:btnInstall.Content = "Install ($count)"
        } else {
            $script:btnInstall.Content = "Install"
        }
    }

    function script:Update-ProviderUI {
        $isChoco = ($script:pkgProvider -eq 'choco')
        if ($script:btnBackendWinget -and $script:btnBackendChoco) {
            $primaryStyle = $script:win.Resources["PrimaryButton"]
            $pillStyle = $script:win.Resources["PillButton"]
            if ($isChoco) {
                $script:btnBackendWinget.Style = $pillStyle
                $script:btnBackendWinget.FontWeight = [System.Windows.FontWeights]::Normal
                $script:btnBackendChoco.Style = $primaryStyle
                $script:btnBackendChoco.FontWeight = [System.Windows.FontWeights]::SemiBold
            } else {
                $script:btnBackendChoco.Style = $pillStyle
                $script:btnBackendChoco.FontWeight = [System.Windows.FontWeights]::Normal
                $script:btnBackendWinget.Style = $primaryStyle
                $script:btnBackendWinget.FontWeight = [System.Windows.FontWeights]::SemiBold
            }
        }

        $provName = if ($isChoco) { "Chocolatey" } else { "WinGet" }
        if ($script:txtSearchPlaceholder) { $script:txtSearchPlaceholder.Text = "Search apps (Enter for $provName)..." }
        if ($script:lblSearchResultTitle) { $script:lblSearchResultTitle.Text = "$provName Search Results" }

        foreach ($chk in $script:checkBoxes) {
            $app = if ($script:registeredApps.ContainsKey($chk.Uid)) { $script:registeredApps[$chk.Uid] } else { $null }
            if ($isChoco -and $app -and -not $app.ChocoId) {
                $chk.IsChecked = $false
                $chk.IsEnabled = $false
                $chk.Opacity = 0.45
                $chk.ToolTip = "Not available in Chocolatey"
            } else {
                $chk.IsEnabled = $true
                $chk.Opacity = 1.0
                $chk.ToolTip = $null
            }
        }
        Update-InstallCount
    }

    function script:Ensure-ProviderReady {
        param(
            [string]$Provider = $script:pkgProvider,
            [switch]$PromptIfMissing,
            [switch]$ContinueOnSuccess
        )

        $isChoco = ($Provider -eq 'choco')
        $existing = if ($isChoco) { Get-ChocoExecutable } else { Get-WinGetExecutable }
        if ($existing) { return $true }

        $provLabel = if ($isChoco) { "Chocolatey" } else { "WinGet" }
        if ($PromptIfMissing) {
            $ans = [System.Windows.MessageBox]::Show(
                "$provLabel is not installed on this PC.`nInstall $provLabel now?",
                "WinKit - $provLabel",
                4, 32
            )
            if ($ans -ne [System.Windows.MessageBoxResult]::Yes) { return $false }
        }

        Open-ProgressOverlay
        $script:winControls.LblProgressTitle.Text = "Installing $provLabel..."
        $script:winControls.LblProgress.Text = "Downloading and installing $provLabel..."
        $script:winControls.PbInstall.IsIndeterminate = $true
        $script:TxtLog.AppendText("---> Installing $provLabel...`n")
        Invoke-DoEvents

        $setupLog = $script:TxtLog.Text
        $ok = $false
        try {
            if ($isChoco) {
                $out = Install-ChocolateyClient *>&1 | Out-String
            } else {
                $out = Install-WinGetClient *>&1 | Out-String
            }
            if ($out) {
                $script:TxtLog.AppendText($out)
                $setupLog += $out
            }
            $ok = [bool](if ($isChoco) { Get-ChocoExecutable } else { Get-WinGetExecutable })
        } catch {
            $errLine = "`n[!] $provLabel installation failed: $_`n"
            $script:TxtLog.AppendText($errLine)
            $setupLog += $errLine
            $ok = $false
        }

        if ($ok -and $ContinueOnSuccess) {
            return $true
        }

        $resCard = @(@{
            App       = @{ Name = $provLabel }
            Code      = $(if ($ok) { 0 } else { -1 })
            Cancelled = $false
            Log       = $setupLog
        })
        Show-InstallSummaryCards -InstallResults $resCard -WinControls $script:winControls -Title "$provLabel Setup"
        if ($script:btnInstall) { $script:btnInstall.IsEnabled = $true }
        if ($script:btnUpgradeAll) { $script:btnUpgradeAll.IsEnabled = $true }
        return $ok
    }

    function script:Set-PackageProvider {
        param([string]$Provider)
        if ($Provider -eq $script:pkgProvider) { return }
        if ($Provider -eq 'choco' -and -not (Ensure-ProviderReady -Provider 'choco' -PromptIfMissing)) { return }

        $script:pkgProvider = $Provider
        Clear-OnlineSearchResults
        Show-CategoryView
        $script:installedPackages = @{}
        Update-AppInstalledBadge
        Update-ProviderUI
        Start-BackgroundPackageDetection
    }

    function script:Show-CategoryView {
        $script:searchSeq++
        if ($script:searchResultsView) { $script:searchResultsView.Visibility = "Collapsed" }
        if ($script:pbSearchLoading) { $script:pbSearchLoading.Visibility = "Collapsed" }
        if ($script:tabCats) {
            $script:tabCats.Visibility = "Visible"
            $script:tabCats.IsEnabled = $true
            $script:tabCats.Opacity = 1.0
        }
    }

    function script:Show-SearchResultView {
        if ($script:tabCats) {
            $script:tabCats.Visibility = "Collapsed"
        }
        if ($script:searchResultsView) { $script:searchResultsView.Visibility = "Visible" }
    }

    function script:Update-AppInstalledBadge {
        if ($null -eq $script:installedPackages) { return }
        $brushGreen = $global:brushConverter.ConvertFromString("#107C41")
        $brushYellow = $global:brushConverter.ConvertFromString("#DCA200")
        $provLabel = if ($script:pkgProvider -eq 'choco') { "Chocolatey" } else { "WinGet" }

        foreach ($app in $global:apps) {
            if (-not $script:appStatusLabels.ContainsKey($app.Id)) { continue }
            $lbl = $script:appStatusLabels[$app.Id]
            $lookupId = Get-AppPackageId -App $app -Provider $script:pkgProvider
            if ($lookupId -and $script:installedPackages.ContainsKey($lookupId)) {
                $info = $script:installedPackages[$lookupId]
                if ($info.Available) {
                    $lbl.Text = "Installed (v$($info.Version)) • Update: v$($info.Available)"
                    $lbl.Foreground = $brushYellow
                    $lbl.ToolTip = "Installed: $($info.Version). Available in ${provLabel}: $($info.Available)"
                } else {
                    $verStr = if ($info.Version -and $info.Version -ne "Unknown") { " (v$($info.Version))" } else { "" }
                    $lbl.Text = "Installed$verStr"
                    $lbl.Foreground = $brushGreen
                    $lbl.ToolTip = "Installed and up to date"
                }
                $lbl.Visibility = "Visible"
            } else {
                $lbl.Visibility = "Collapsed"
            }
        }
    }

    function script:Start-BackgroundTask {
        param(
            [scriptblock]$Worker,
            [object[]]$Arguments = @(),
            $Context = $null,
            [scriptblock]$OnComplete
        )
        try {
            $runspace = [runspacefactory]::CreateRunspace()
            $runspace.Open()
            $ps = [powershell]::Create()
            $ps.Runspace = $runspace
            $null = $ps.AddScript($Worker)
            foreach ($arg in $Arguments) { $null = $ps.AddArgument($arg) }

            $asyncResult = $ps.BeginInvoke()
            $timer = New-Object System.Windows.Threading.DispatcherTimer
            $timer.Interval = [TimeSpan]::FromMilliseconds(150)
            $timer.Tag = @{ Ps = $ps; Runspace = $runspace; Async = $asyncResult; Context = $Context; OnComplete = $OnComplete }
            $timer.Add_Tick({
                param($sender, $e)
                $null = $e
                $state = $sender.Tag
                if ($state.Async.IsCompleted) {
                    $sender.Stop()
                    $res = $null
                    $err = $null
                    try {
                        $res = $state.Ps.EndInvoke($state.Async)
                    } catch {
                        $err = $_
                    } finally {
                        $state.Ps.Dispose()
                        $state.Runspace.Close()
                        $state.Runspace.Dispose()
                    }
                    & $state.OnComplete $res $err $state.Context
                }
            })
            $timer.Start()
        } catch {
            & $OnComplete $null $_ $Context
        }
    }

    function script:Start-BackgroundPackageDetection {
        $prov = $script:pkgProvider
        if ($prov -eq 'choco') {
            $chocoExe = Get-ChocoExecutable
            if (-not $chocoExe) { return }
            $worker = {
                param([string]$exe)
                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                @{
                    List     = @(& $exe list -r 2>$null)
                    Outdated = @(& $exe outdated -r 2>$null)
                }
            }
            Start-BackgroundTask -Worker $worker -Arguments @($chocoExe) -Context @{ Provider = 'choco' } -OnComplete {
                param($res, $err, $ctx)
                if ($err -or -not $res -or $ctx.Provider -ne $script:pkgProvider) { return }
                $data = $res | Select-Object -First 1
                $installed = [hashtable]::new([System.StringComparer]::OrdinalIgnoreCase)
                foreach ($item in @(ConvertFrom-ChocoLines -Lines $data.List)) {
                    $installed[$item.Id] = @{ Version = $item.Version; Available = "" }
                }
                foreach ($upd in @(ConvertFrom-ChocoLines -Lines $data.Outdated -Outdated)) {
                    if ($installed.ContainsKey($upd.Id)) {
                        $installed[$upd.Id].Available = $upd.Available
                    } else {
                        $installed[$upd.Id] = @{ Version = $upd.Version; Available = $upd.Available }
                    }
                }
                $script:installedPackages = $installed
                Update-AppInstalledBadge
            }
            return
        }

        $wingetExe = Get-WinGetExecutable
        if (-not $wingetExe) { return }
        $worker = {
            param([string]$exe)
            [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
            & $exe list --source winget --accept-source-agreements 2>$null
        }
        Start-BackgroundTask -Worker $worker -Arguments @($wingetExe) -Context @{ Provider = 'winget' } -OnComplete {
            param($lines, $err, $ctx)
            if ($err -or -not $lines -or $ctx.Provider -ne $script:pkgProvider) { return }
            $installed = @{}
            foreach ($item in (ConvertFrom-WingetTable -Lines $lines)) {
                $installed[$item.Id] = @{
                    Version   = $item.Version
                    Available = $item.Available
                }
            }
            $script:installedPackages = $installed
            Update-AppInstalledBadge
        }
    }

    # Populate categories and apps
    for ($c = 0; $c -lt $global:cats.Count; $c++) {
        $tabItem = New-Object System.Windows.Controls.TabItem
        $tabItem.Header = $global:cats[$c]
        $scroll = New-Object System.Windows.Controls.ScrollViewer
        $scroll.VerticalScrollBarVisibility = "Auto"
        $scroll.FocusVisualStyle = $null
        $wrap = New-Object System.Windows.Controls.WrapPanel
        $wrap.Margin = "5"
        
        $catApps = $global:apps | Where-Object { $_.Cat -eq $c }
        foreach ($app in $catApps) {
            $script:registeredApps[$app.Name] = $app
            $panel = New-Object System.Windows.Controls.StackPanel
            $panel.Orientation = "Vertical"
            $panel.Width = 230
            $panel.Margin = "0,0,0,8"
            $panel.Tag = @{ App = $app; CatIndex = $c }
            
            $chk = New-Object System.Windows.Controls.CheckBox
            $chk.Content = $app.Name
            $chk.IsChecked = $app.Sel
            $chk.Uid = $app.Name
            $chk.Add_Checked({ Update-InstallCount })
            $chk.Add_Unchecked({ Update-InstallCount })
            $panel.Children.Add($chk) | Out-Null
            $script:checkBoxes += $chk

            $lblStatus = New-Object System.Windows.Controls.TextBlock
            $lblStatus.FontSize = 10
            $lblStatus.Margin = "28,1,0,0"
            $lblStatus.Visibility = "Collapsed"
            $panel.Children.Add($lblStatus) | Out-Null
            $script:appStatusLabels[$app.Id] = $lblStatus
            
            if ($app.Dep) {
                $chkDep = New-Object System.Windows.Controls.CheckBox
                $chkDep.Content = "+ $($app.Dep)"
                $chkDep.IsChecked = $true
                $chkDep.Visibility = "Collapsed"
                $chkDep.Margin = "25,2,0,0"
                $chkDep.ToolTip = "Uncheck to skip installing $($app.Dep)"
                
                $global:depCheckBoxes[$app.Name] = $chkDep
                
                $chk.Tag = $chkDep
                $chk.Add_Checked({ $this.Tag.Visibility = "Visible" })
                $chk.Add_Unchecked({ $this.Tag.Visibility = "Collapsed" })
                
                $panel.Children.Add($chkDep) | Out-Null
            }
            
            $wrap.Children.Add($panel) | Out-Null
            $script:appPanels += $panel
        }
        
        $scroll.Content = $wrap
        $tabItem.Content = $scroll
        $script:tabCats.Items.Add($tabItem) | Out-Null
    }

    function script:Clear-OnlineSearchResults {
        if ($script:searchResultsWrap) { $script:searchResultsWrap.Children.Clear() }
        $script:onlineCheckBoxes = @()
        Update-InstallCount
    }

    function script:Add-OnlineResultCard {
        param($Item, [bool]$IsChecked = $false, [string]$Provider = $script:pkgProvider)

        $card = New-Object System.Windows.Controls.Border
        $card.Background = $script:win.Resources["ControlBg"]
        $card.BorderBrush = $script:win.Resources["BorderClr"]
        $card.BorderThickness = 1
        $card.CornerRadius = 6
        $card.Padding = "8,6,8,6"
        $card.Margin = "0,0,10,10"
        $card.Width = 230

        $cardPanel = New-Object System.Windows.Controls.StackPanel
        $cardPanel.Orientation = "Vertical"

        $chk = New-Object System.Windows.Controls.CheckBox
        $chk.Content = $Item.Name
        $chk.Uid = $Item.Id
        $chk.IsChecked = $IsChecked
        $chk.Margin = "0,0,0,2"

        $script:registeredApps[$Item.Id] = @{
            Name     = $Item.Name
            Id       = $Item.Id
            ChocoId  = if ($Provider -eq 'choco') { $Item.Id } else { $null }
            Cat      = 99
            Sel      = $false
            Provider = $Provider
        }
        $script:onlineCheckBoxes += $chk

        $chk.Add_Checked({ Update-InstallCount })
        $chk.Add_Unchecked({ Update-InstallCount })
        $cardPanel.Children.Add($chk) | Out-Null

        $subText = New-Object System.Windows.Controls.TextBlock
        $verDisplay = if ($Item.Version) { " • v$($Item.Version)" } else { "" }
        $subText.Text = "$($Item.Id)$verDisplay"
        $subText.FontSize = 10
        $subText.Opacity = 0.6
        $subText.Margin = "28,0,0,0"
        $subText.Foreground = $script:win.Resources["AppText"]
        $subText.TextTrimming = "CharacterEllipsis"
        $subText.ToolTip = "$($Item.Name) ($($Item.Id))"
        $cardPanel.Children.Add($subText) | Out-Null

        if ($script:installedPackages.ContainsKey($Item.Id)) {
            $appInstalledInfo = $script:installedPackages[$Item.Id]
            $badge = New-Object System.Windows.Controls.TextBlock
            $badge.FontSize = 10
            $badge.Margin = "28,2,0,0"
            if ($appInstalledInfo.Available) {
                $badge.Text = "Installed (v$($appInstalledInfo.Version)) • Update: v$($appInstalledInfo.Available)"
                $badge.Foreground = $global:brushConverter.ConvertFromString("#DCA200")
            } else {
                $badge.Text = "Installed (v$($appInstalledInfo.Version))"
                $badge.Foreground = $global:brushConverter.ConvertFromString("#107C41")
            }
            $cardPanel.Children.Add($badge) | Out-Null
        }

        $card.Child = $cardPanel
        if ($script:searchResultsWrap) { $script:searchResultsWrap.Children.Add($card) | Out-Null }
    }

    $script:doOnlineSearch = {
        param([string]$query)
        $q = $query.Trim()
        if (-not $q) { return }

        $prov = $script:pkgProvider
        $provLabel = if ($prov -eq 'choco') { 'Chocolatey' } else { 'WinGet' }
        if (-not (Ensure-ProviderReady -Provider $prov -PromptIfMissing)) { return }
        $cliExe = if ($prov -eq 'choco') { Get-ChocoExecutable } else { Get-WinGetExecutable }

        $script:searchSeq++
        $seq = $script:searchSeq

        Show-SearchResultView
        if ($script:lblSearchResultStatus) {
            $script:lblSearchResultStatus.Text = "Searching $provLabel repository for `"$q`"..."
            $script:lblSearchResultStatus.Opacity = 1.0
        }
        if ($script:pbSearchLoading) { $script:pbSearchLoading.Visibility = "Visible" }
        Clear-OnlineSearchResults

        if ($prov -eq 'choco') {
            $worker = {
                param([string]$searchTerm, [string]$exe)
                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                & $exe search $searchTerm -r --page-size=25 2>$null
            }
            $workerArgs = @($q, $cliExe)
        } else {
            $worker = {
                param([string]$searchTerm, [string]$exe)
                [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
                & $exe search --query $searchTerm --source winget --accept-source-agreements --count 25 2>$null
            }
            $workerArgs = @($q, $cliExe)
        }

        Start-BackgroundTask -Worker $worker -Arguments $workerArgs -Context @{ Seq = $seq; Query = $q; Provider = $prov; Label = $provLabel } -OnComplete {
            param($lines, $err, $ctx)
            if ($ctx.Seq -ne $script:searchSeq -or $ctx.Provider -ne $script:pkgProvider) { return }
            if ($script:pbSearchLoading) { $script:pbSearchLoading.Visibility = "Collapsed" }

            if ($err) {
                if ($script:lblSearchResultStatus) {
                    $script:lblSearchResultStatus.Text = "Search error: $err"
                    $script:lblSearchResultStatus.Opacity = 1.0
                }
                return
            }

            $foundApps = if ($ctx.Provider -eq 'choco') {
                @(ConvertFrom-ChocoLines -Lines $lines)
            } else {
                @(ConvertFrom-WingetTable -Lines $lines)
            }
            Clear-OnlineSearchResults
            if ($foundApps.Count -eq 0) {
                if ($script:lblSearchResultStatus) {
                    $script:lblSearchResultStatus.Text = "No packages found for `"$($ctx.Query)`" in $($ctx.Label) repository."
                    $script:lblSearchResultStatus.Opacity = 0.8
                }
                return
            }

            if ($script:lblSearchResultStatus) {
                $script:lblSearchResultStatus.Text = "Found $($foundApps.Count) package(s) for `"$($ctx.Query)`". Select to include in installation:"
                $script:lblSearchResultStatus.Opacity = 0.8
            }

            foreach ($item in $foundApps) {
                Add-OnlineResultCard -Item $item -Provider $ctx.Provider
            }
        }
    }

    if ($script:btnBackToCats) {
        $script:btnBackToCats.Add_Click({
            Show-CategoryView
        })
    }

    # Top search filter & WinGet lookup handlers
    if ($script:txtSearch) {
        $script:txtSearch.Add_GotFocus({
            if ($script:txtSearchPlaceholder) { $script:txtSearchPlaceholder.Visibility = "Collapsed" }
            if ($script:tabCats -and $script:searchResultsView.Visibility -ne "Visible") {
                $script:tabCats.Opacity = 0.5
            }
            if ($script:txtSearch.Text) { $script:txtSearch.SelectAll() }
        })

        $script:txtSearch.Add_LostFocus({
            if (-not $script:txtSearch.Text.Trim()) {
                if ($script:txtSearchPlaceholder) { $script:txtSearchPlaceholder.Visibility = "Visible" }
            }
            if ($script:tabCats -and $script:searchResultsView.Visibility -ne "Visible") {
                $script:tabCats.IsEnabled = $true
                $script:tabCats.Opacity = 1.0
            }
        })

        $script:txtSearch.Add_TextChanged({
            $q = $script:txtSearch.Text.Trim()
            if ($q) {
                if ($script:txtSearchPlaceholder) { $script:txtSearchPlaceholder.Visibility = "Collapsed" }
                if ($script:btnClearSearch) { $script:btnClearSearch.Visibility = "Visible" }
            } else {
                if (-not $script:txtSearch.IsFocused -and $script:txtSearchPlaceholder) {
                    $script:txtSearchPlaceholder.Visibility = "Visible"
                }
                if ($script:btnClearSearch) { $script:btnClearSearch.Visibility = "Collapsed" }
                Clear-OnlineSearchResults
                Show-CategoryView
            }

            $firstMatchingTab = -1
            $currentTabHasMatch = $false
            $currTabIdx = $script:tabCats.SelectedIndex

            foreach ($p in $script:appPanels) {
                $app = $p.Tag.App
                $catIdx = $p.Tag.CatIndex
                if (-not $q -or ($app.Name.IndexOf($q, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)) {
                    $p.Visibility = "Visible"
                    if ($catIdx -eq $currTabIdx) { $currentTabHasMatch = $true }
                    if ($firstMatchingTab -eq -1) { $firstMatchingTab = $catIdx }
                } else {
                    $p.Visibility = "Collapsed"
                }
            }

            if ($q -and -not $currentTabHasMatch -and $firstMatchingTab -ge 0) {
                $script:tabCats.SelectedIndex = $firstMatchingTab
            }
        })

        $script:txtSearch.Add_PreviewKeyDown({
            param($s, $e)
            $null = $s
            if ($e.Key -eq [System.Windows.Input.Key]::Enter) {
                $e.Handled = $true
                $q = $script:txtSearch.Text.Trim()
                if ($q) {
                    & $script:doOnlineSearch $q
                }
            }
        })
    }

    if ($script:btnClearSearch) {
        $script:btnClearSearch.Add_Click({
            $script:txtSearch.Text = ""
            Clear-OnlineSearchResults
            Show-CategoryView
        })
    }

    # Click on background or categories reactivates categories and unfocuses search
    $script:win.Add_PreviewMouseDown({
        param($s, $e)
        $null = $s
        if ($script:txtSearch -and $script:txtSearch.IsFocused) {
            $pos = $e.GetPosition($script:txtSearch)
            $isInside = ($pos.X -ge 0 -and $pos.X -le $script:txtSearch.ActualWidth -and 
                         $pos.Y -ge 0 -and $pos.Y -le $script:txtSearch.ActualHeight)

            if (-not $isInside -and $script:btnClearSearch -and $script:btnClearSearch.Visibility -eq "Visible") {
                $posClear = $e.GetPosition($script:btnClearSearch)
                if ($posClear.X -ge 0 -and $posClear.X -le $script:btnClearSearch.ActualWidth -and 
                    $posClear.Y -ge 0 -and $posClear.Y -le $script:btnClearSearch.ActualHeight) {
                    $isInside = $true
                }
            }

            if (-not $isInside) {
                if ($script:tabCats -and $script:searchResultsView.Visibility -ne "Visible") {
                    $script:tabCats.IsEnabled = $true
                    $script:tabCats.Opacity = 1.0
                }

                if (-not $script:txtSearch.Text.Trim() -and $script:txtSearchPlaceholder) {
                    $script:txtSearchPlaceholder.Visibility = "Visible"
                }

                [System.Windows.Input.Keyboard]::ClearFocus()
            }
        }
    })

    # Theme toggle handler
    $script:btnTheme.Add_Click({
        $global:isDark = -not $global:isDark
        if ($global:isDark) { Set-Theme $global:darkPalette } else { Set-Theme $global:lightPalette }
        Update-AppTheme -fromManualClick $true
    })

    # Debug console toggle handler
    $script:btnDebug.Add_Click({
        if ($script:isConsoleVisible) {
            [Console.Window]::ShowWindow([Console.Window]::GetConsoleWindow(), 0) | Out-Null
            $script:isConsoleVisible = $false
        } else {
            [Console.Window]::ShowWindow([Console.Window]::GetConsoleWindow(), 5) | Out-Null
            $script:isConsoleVisible = $true
        }
    })

    # Package manager toggle handlers
    if ($script:btnBackendWinget) {
        $script:btnBackendWinget.Add_Click({ Set-PackageProvider 'winget' })
    }
    if ($script:btnBackendChoco) {
        $script:btnBackendChoco.Add_Click({ Set-PackageProvider 'choco' })
    }

    # Preset handlers
    $script:btnSelectAll.Add_Click({
        foreach ($chk in $script:checkBoxes) {
            if ($chk.IsEnabled) { $chk.IsChecked = $true }
        }
        Update-InstallCount
    })

    $script:btnClearAll.Add_Click({
        foreach ($chk in ($script:checkBoxes + $script:onlineCheckBoxes)) { $chk.IsChecked = $false }
        Update-InstallCount
    })

    function script:Open-ProgressOverlay {
        if ($script:btnInstall) { $script:btnInstall.IsEnabled = $false }
        if ($script:btnUpgradeAll) { $script:btnUpgradeAll.IsEnabled = $false }

        $script:ProgressOverlay.Visibility = "Visible"
        $script:TxtLog.Visibility = "Visible"
        $script:SummaryScroll.Visibility = "Collapsed"
        $script:SummaryPanel.Children.Clear()

        if (-not $global:isDark) {
            $script:TxtLog.Background = $global:brushConverter.ConvertFromString("#F0F0F0")
            $script:TxtLog.Foreground = $global:brushConverter.ConvertFromString("#111111")
        } else {
            $script:TxtLog.Background = $global:brushConverter.ConvertFromString("#1E1E1E")
            $script:TxtLog.Foreground = $global:brushConverter.ConvertFromString("#CCCCCC")
        }

        $global:cancelInstall = $false
        $script:TxtLog.Text = ""
        $script:btnCancelInstall.Content = "Cancel"
        $script:btnCancelInstall.IsEnabled = $true
        if ($script:btnExportLog) { $script:btnExportLog.Visibility = "Collapsed" }
        Invoke-DoEvents
    }

    # Upgrade All handler
    if ($script:btnUpgradeAll) {
        $script:btnUpgradeAll.Add_Click({
            $prov = $script:pkgProvider
            if (-not (Ensure-ProviderReady -Provider $prov -ContinueOnSuccess)) { return }
            if ($script:ProgressOverlay.Visibility -ne "Visible") { Open-ProgressOverlay }
            try {
                Start-SystemUpgrade $script:winControls -Provider $prov
            } finally {
                if ($script:btnInstall) { $script:btnInstall.IsEnabled = $true }
                if ($script:btnUpgradeAll) { $script:btnUpgradeAll.IsEnabled = $true }
                Start-BackgroundPackageDetection
            }
        })
    }

    # Preset save handler (supports .json schema and legacy .txt)
    $script:btnSave.Add_Click({
        $selectedApps = @(Get-SelectedApps)
        if ($selectedApps.Count -eq 0) {
            [System.Windows.MessageBox]::Show("No applications are selected to save.", "WinKit Preset", 0, 48)
            return
        }

        $sfd = New-Object Microsoft.Win32.SaveFileDialog
        $sfd.Title = "Save WinKit Preset"
        $sfd.Filter = "WinGet Package List (*.json)|*.json|WinKit Preset (*.txt)|*.txt|All Files (*.*)|*.*"
        $sfd.FileName = "winkit-packages.json"
        $docs = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
        if ($docs -and (Test-Path $docs)) { $sfd.InitialDirectory = $docs }

        if ($sfd.ShowDialog() -eq $true) {
            try {
                $ids = @($selectedApps | ForEach-Object {
                    $p = if ($_.Provider) { $_.Provider } else { $script:pkgProvider }
                    Get-AppPackageId -App $_ -Provider $p
                } | Where-Object { $_ })
                if ($sfd.FileName.EndsWith(".json", [System.StringComparison]::OrdinalIgnoreCase)) {
                    $json = ConvertTo-WinKitPresetJson -PackageIds $ids
                    [System.IO.File]::WriteAllText($sfd.FileName, $json, [System.Text.UTF8Encoding]::new($false))
                } else {
                    [System.IO.File]::WriteAllText($sfd.FileName, ($ids -join "`n"), [System.Text.UTF8Encoding]::new($false))
                }
                [System.Windows.MessageBox]::Show("Preset saved successfully to:`n$($sfd.FileName)", "Success", 0, 64)
            } catch {
                [System.Windows.MessageBox]::Show("Failed to save preset: $_", "Error", 0, 16)
            }
        }
    })

    # Preset load handler (supports .json schema and legacy .txt)
    $script:btnLoad.Add_Click({
        $ofd = New-Object Microsoft.Win32.OpenFileDialog
        $ofd.Title = "Load Preset or Package List"
        $ofd.Filter = "Supported Presets (*.json;*.txt)|*.json;*.txt|WinGet Package List (*.json)|*.json|WinKit Preset (*.txt)|*.txt|All Files (*.*)|*.*"
        $ofd.FileName = "winkit-packages.json"
        $docs = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
        if ($docs -and (Test-Path $docs)) { $ofd.InitialDirectory = $docs }

        if ($ofd.ShowDialog() -eq $true) {
            if (Test-Path $ofd.FileName) {
                try {
                    $targetIds = @(Import-WinKitPresetIds -Path $ofd.FileName)
                    Clear-OnlineSearchResults

                    $matchedTargets = @{}
                    foreach ($chk in $script:checkBoxes) {
                        $app = if ($script:registeredApps.ContainsKey($chk.Uid)) { $script:registeredApps[$chk.Uid] } else { $null }
                        $isMatch = ($null -ne $app -and ($targetIds -contains $app.Id -or ($app.ChocoId -and $targetIds -contains $app.ChocoId) -or $targetIds -contains $app.Name)) -or ($targetIds -contains $chk.Uid)
                        $chk.IsChecked = ($isMatch -and $chk.IsEnabled)
                        if ($isMatch -and $null -ne $app) {
                            $matchedTargets[$app.Id] = $true
                            if ($app.ChocoId) { $matchedTargets[$app.ChocoId] = $true }
                            $matchedTargets[$app.Name] = $true
                        }
                    }

                    $customCount = 0
                    $prov = $script:pkgProvider
                    foreach ($tid in $targetIds) {
                        $validCustom = (Test-SafePackageId $tid) -and ($prov -eq 'choco' -or $tid.Contains('.'))
                        if (-not $matchedTargets.ContainsKey($tid) -and $validCustom) {
                            $matchedTargets[$tid] = $true
                            Add-OnlineResultCard -Item ([PSCustomObject]@{ Name = $tid; Id = $tid; Version = "" }) -IsChecked $true -Provider $prov
                            $customCount++
                        }
                    }

                    Update-InstallCount
                    $totalSelected = @(Get-SelectedApps).Count
                    $provLabel = if ($prov -eq 'choco') { 'Chocolatey' } else { 'WinGet' }
                    $extraMsg = if ($customCount -gt 0) { "`n($customCount custom $provLabel package(s) added to search results)" } else { "" }
                    [System.Windows.MessageBox]::Show("Loaded preset with $totalSelected selected application(s).$extraMsg", "WinKit", 0, 64)
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to load preset: $_", "Error", 0, 16)
                }
            }
        }
    })

    # Export Log handler
    if ($script:btnExportLog) {
        $script:btnExportLog.Add_Click({
            $logContent = $script:TxtLog.Text
            if (-not $logContent) {
                [System.Windows.MessageBox]::Show("No installation log available to export.", "WinKit Export", 0, 48)
                return
            }

            $sfd = New-Object Microsoft.Win32.SaveFileDialog
            $sfd.Title = "Export Installation Log"
            $sfd.Filter = "Log File (*.log)|*.log|Text File (*.txt)|*.txt|All Files (*.*)|*.*"
            $sfd.FileName = "winkit-install-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
            $docs = [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
            if ($docs -and (Test-Path $docs)) { $sfd.InitialDirectory = $docs }

            if ($sfd.ShowDialog() -eq $true) {
                try {
                    [System.IO.File]::WriteAllText($sfd.FileName, $logContent, [System.Text.UTF8Encoding]::new($false))
                    [System.Windows.MessageBox]::Show("Log exported successfully to:`n$($sfd.FileName)", "WinKit", 0, 64)
                } catch {
                    [System.Windows.MessageBox]::Show("Failed to save log: $_", "Error", 0, 16)
                }
            }
        })
    }

    # Install cancel / close handler
    $global:cancelInstall = $false
    $global:isInstallFinished = $false
    $script:btnCancelInstall.Add_Click({
        if ($this.Content -eq "Close" -or $global:isInstallFinished) {
            $script:ProgressOverlay.Visibility = "Collapsed"
            $script:btnInstall.IsEnabled = $true
            if ($script:btnUpgradeAll) { $script:btnUpgradeAll.IsEnabled = $true }
        } else {
            $global:cancelInstall = $true
            $this.Content = "Cancelling..."
            $this.IsEnabled = $false
        }
    })

    # Install button handler
    $script:btnInstall.Add_Click({
        $toInstall = @(Get-SelectedApps)
        if ($toInstall.Count -eq 0) { return }
        $prov = $script:pkgProvider
        if (-not (Ensure-ProviderReady -Provider $prov -ContinueOnSuccess)) { return }
        Write-Host "Install button clicked ($prov). Selected apps: $($toInstall.Count)" -ForegroundColor Cyan

        if ($script:ProgressOverlay.Visibility -ne "Visible") { Open-ProgressOverlay }
        try {
            Start-AppsInstallation $toInstall $script:winControls -Provider $prov
        } finally {
            $script:btnInstall.IsEnabled = $true
            if ($script:btnUpgradeAll) { $script:btnUpgradeAll.IsEnabled = $true }
            Start-BackgroundPackageDetection
        }
    })

    # Window DWM & Backdrop initialization
    $script:win.Add_SourceInitialized({
        $helper = New-Object System.Windows.Interop.WindowInteropHelper($script:win)
        $hwnd = $helper.Handle
        
        $margins = New-Object Dwm+MARGINS
        $margins.cxLeftWidth = -1
        $margins.cxRightWidth = -1
        $margins.cyTopHeight = -1
        $margins.cyBottomHeight = -1
        [Dwm]::DwmExtendFrameIntoClientArea($hwnd, [ref]$margins) | Out-Null
        
        $val = if ($global:isDark) { 1 } else { 0 }
        [Dwm]::DwmSetWindowAttribute($hwnd, 20, [ref]$val, 4) | Out-Null
        
        if ($global:isWin11) {
            $backdrop = 2
            [Dwm]::DwmSetWindowAttribute($hwnd, 38, [ref]$backdrop, 4) | Out-Null

            $micaFallback = 1
            [Dwm]::DwmSetWindowAttribute($hwnd, 1029, [ref]$micaFallback, 4) | Out-Null

            $hwndSource = [System.Windows.Interop.HwndSource]::FromHwnd($hwnd)
            if ($null -ne $hwndSource) {
                $hwndSource.CompositionTarget.BackgroundColor = [System.Windows.Media.Colors]::Transparent
            }
        }
    })

    # Window cleanup
    $script:win.Add_Closed({
        Unregister-ThemeListener
    })

    # Initialize provider toggle UI and start background scan for installed packages & updates
    Update-ProviderUI
    Start-BackgroundPackageDetection
}