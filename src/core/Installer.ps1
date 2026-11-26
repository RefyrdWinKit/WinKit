# --- WinKit Installation Engine ---

function Test-SafePackageId {
    param([string]$Id)
    return (-not [string]::IsNullOrWhiteSpace($Id)) -and ($Id -match '^[a-zA-Z0-9._+\-]+$')
}

function Get-WinGetExecutable {
    $cmd = Get-Command "winget.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $winApps = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\winget.exe"
    if (Test-Path $winApps) {
        $dir = Split-Path -Parent $winApps
        if (-not ($env:PATH -like "*$dir*")) { $env:PATH += ";$dir" }
        return $winApps
    }
    return $null
}

function Install-WinGetClient {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    if (-not (Get-PackageProvider -ListAvailable -Name NuGet -ErrorAction SilentlyContinue)) {
        Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -Confirm:$false | Out-Null
    }
    Set-PSRepository -Name "PSGallery" -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    Install-Module -Name Microsoft.WinGet.Client -Force -Confirm:$false -Scope AllUsers -ErrorAction Stop
    Import-Module Microsoft.WinGet.Client -Force -ErrorAction Stop
    if (Get-Command Repair-WinGetPackageManager -ErrorAction SilentlyContinue) {
        Repair-WinGetPackageManager -Latest -Force -ErrorAction Stop
    }
    $env:PATH = [Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [Environment]::GetEnvironmentVariable("Path", "User")
    $null = Get-WinGetExecutable
}

function Get-ChocoExecutable {
    $cmd = Get-Command "choco.exe" -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    $defaultPath = Join-Path $env:ProgramData "chocolatey\bin\choco.exe"
    if (Test-Path $defaultPath) { return $defaultPath }
    return $null
}

function Install-ChocolateyClient {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Set-ExecutionPolicy Bypass -Scope Process -Force
    $tmpChoco = Join-Path $env:TEMP "choco_install_$PID.ps1"
    try {
        Invoke-WebRequest -Uri 'https://community.chocolatey.org/install.ps1' -OutFile $tmpChoco -UseBasicParsing
        & $tmpChoco
    } finally {
        Remove-Item $tmpChoco -Force -ErrorAction SilentlyContinue
    }
    $chocoBin = Join-Path $env:ProgramData "chocolatey\bin"
    if ((Test-Path $chocoBin) -and -not ($env:PATH -like "*$chocoBin*")) {
        $env:PATH += ";$chocoBin"
    }
}

function Get-AppPackageId {
    param($App, [string]$Provider = 'winget')
    if ($Provider -eq 'choco') { return $App.ChocoId }
    return $App.Id
}

function Get-InstallResultStatus {
    param([int]$Code, [string]$Log = "", [bool]$Cancelled = $false)

    if ($Cancelled) {
        return @{ Color = "#FFA500"; Text = "Cancelled"; Desc = "Installation was cancelled by the user." }
    }

    $alreadyInstalledCodes = @(-1978335220, 2316632076, -1978335189, 2316632107, -1978335187, 2316632109, -1978335190, 2316632106)
    $alreadyInstalledRegex = "(?i)(No (?:newer|available|applicable) (?:package|upgrade|update)|найден.*установленный пакет.*не найдено|не найдено.*обновлен|не найдено.*верси|уже установлен|установлена последняя версия|already installed.*no (?:newer|available|upgrade)|is already installed|already installed\.\s*[\r\n].*installed 0/\d+ packages|Chocolatey upgraded 0/\d+ packages)"
    $didFreshInstall = ($Log -match "(?i)(Successfully installed|Успешно установлен|installed [1-9]\d*/\d+ packages|upgraded [1-9]\d*/\d+ packages)")
    $isInstalledNoUpdate = ($Code -in $alreadyInstalledCodes) -or (($Log -match $alreadyInstalledRegex) -and -not $didFreshInstall)
    if ($isInstalledNoUpdate) {
        return @{ Color = "#00BCF9"; Text = "Already installed (Up to date)"; Desc = "The latest version is already installed on your system." }
    }

    $isSuccess = $Code -in @(0, 3010, 1641)
    $isUpgradeAttempt = $Log -match "(?i)(Trying to upgrade|попытка обновить|Upgrading|Обновление пакета|Chocolatey upgraded)"
    if ($isSuccess -and $isUpgradeAttempt) {
        return @{ Color = "#FFC83B"; Text = "Successfully updated"; Desc = "Application was updated to the newest available release." }
    }
    if ($isSuccess) {
        return @{ Color = "#107C41"; Text = "Installed successfully"; Desc = "Completed with exit code $Code." }
    }
    return @{ Color = "#E81123"; Text = "Installation failed"; Desc = "Installer returned error code $Code." }
}

function Show-InstallSummary {
    param($InstallResults, $WinControls, [string]$Title = "Installation Complete")

    $TxtLog = $WinControls.TxtLog
    $LblProgressTitle = $WinControls.LblProgressTitle
    $LblProgress = $WinControls.LblProgress
    $PbInstall = $WinControls.PbInstall
    $BtnCancelInstall = $WinControls.BtnCancelInstall
    $SummaryScroll = $WinControls.SummaryScroll
    $SummaryPanel = $WinControls.SummaryPanel
    $BtnExportLog = $WinControls.BtnExportLog

    $TxtLog.Visibility = "Collapsed"
    $PbInstall.Visibility = "Collapsed"
    $SummaryScroll.Visibility = "Visible"
    $LblProgressTitle.Text = $Title
    $PbInstall.IsIndeterminate = $false
    $PbInstall.Value = 100
    $LblProgress.Text = "Finished!"

    foreach ($res in $InstallResults) {
        $st = Get-InstallResultStatus -Code ([int]$res.Code) -Log ([string]$res.Log) -Cancelled ([bool]$res.Cancelled)
        $statusColor = $st.Color
        $statusText = $st.Text
        $statusDesc = $st.Desc

        $card = New-Object System.Windows.Controls.Border
        $card.Background = $global:win.Resources["ControlBg"]
        $card.BorderBrush = $global:win.Resources["BorderClr"]
        $card.BorderThickness = 1
        $card.CornerRadius = 6
        $card.Margin = "0,0,0,10"
        $card.Padding = "12,10,12,10"

        $cardGrid = New-Object System.Windows.Controls.Grid
        $col1 = New-Object System.Windows.Controls.ColumnDefinition; $col1.Width = [System.Windows.GridLength]::Auto
        $col2 = New-Object System.Windows.Controls.ColumnDefinition; $col2.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star)
        $col3 = New-Object System.Windows.Controls.ColumnDefinition; $col3.Width = [System.Windows.GridLength]::Auto
        $cardGrid.ColumnDefinitions.Add($col1)
        $cardGrid.ColumnDefinitions.Add($col2)
        $cardGrid.ColumnDefinitions.Add($col3)

        $rowTop = New-Object System.Windows.Controls.RowDefinition; $rowTop.Height = [System.Windows.GridLength]::Auto
        $rowBot = New-Object System.Windows.Controls.RowDefinition; $rowBot.Height = [System.Windows.GridLength]::Auto
        $cardGrid.RowDefinitions.Add($rowTop)
        $cardGrid.RowDefinitions.Add($rowBot)

        $statusDot = New-Object System.Windows.Shapes.Ellipse
        $statusDot.Width = 10
        $statusDot.Height = 10
        $statusDot.Fill = $global:brushConverter.ConvertFromString($statusColor)
        $statusDot.VerticalAlignment = "Center"
        $statusDot.Margin = "4,0,12,0"
        [System.Windows.Controls.Grid]::SetColumn($statusDot, 0)
        [System.Windows.Controls.Grid]::SetRow($statusDot, 0)
        $cardGrid.Children.Add($statusDot) | Out-Null

        $titlePanel = New-Object System.Windows.Controls.StackPanel
        $titlePanel.Orientation = "Vertical"
        $titlePanel.VerticalAlignment = "Center"
        [System.Windows.Controls.Grid]::SetColumn($titlePanel, 1)
        [System.Windows.Controls.Grid]::SetRow($titlePanel, 0)

        $appName = New-Object System.Windows.Controls.TextBlock
        $appName.Text = $res.App.Name
        $appName.FontSize = 14
        $appName.FontWeight = [System.Windows.FontWeights]::SemiBold
        $appName.Foreground = $global:win.Resources["AppText"]
        $titlePanel.Children.Add($appName) | Out-Null

        $appSub = New-Object System.Windows.Controls.TextBlock
        $appSub.Text = "$statusText - $statusDesc"
        $appSub.FontSize = 12
        $appSub.Foreground = $global:brushConverter.ConvertFromString($statusColor)
        $titlePanel.Children.Add($appSub) | Out-Null

        $cardGrid.Children.Add($titlePanel) | Out-Null

        $logContainer = New-Object System.Windows.Controls.Border
        $logContainer.Background = $global:brushConverter.ConvertFromString("#181818")
        $logContainer.BorderThickness = 0
        $logContainer.CornerRadius = 4
        $logContainer.Margin = "0,10,0,0"
        $logContainer.Padding = "8"
        $logContainer.Visibility = "Collapsed"
        [System.Windows.Controls.Grid]::SetColumn($logContainer, 0)
        [System.Windows.Controls.Grid]::SetColumnSpan($logContainer, 3)
        [System.Windows.Controls.Grid]::SetRow($logContainer, 1)

        $logBox = New-Object System.Windows.Controls.TextBox
        $logBox.Text = if ($res.Log) { $res.Log } else { "No output captured." }
        $logBox.Background = [System.Windows.Media.Brushes]::Transparent
        $logBox.Foreground = $global:brushConverter.ConvertFromString("#AAAAAA")
        $logBox.FontFamily = "Consolas"
        $logBox.FontSize = 11
        $logBox.IsReadOnly = $true
        $logBox.TextWrapping = "Wrap"
        $logBox.BorderThickness = 0
        $logBox.MaxHeight = 150
        $logBox.VerticalScrollBarVisibility = "Auto"
        $logContainer.Child = $logBox

        $cardGrid.Children.Add($logContainer) | Out-Null

        $btnLog = New-Object System.Windows.Controls.Button
        $btnLog.Content = "Show Log"
        $btnLog.FontSize = 11
        $btnLog.Padding = "10,4,10,4"
        $btnLog.Height = 26
        $btnLog.VerticalAlignment = "Center"
        $btnLog.Tag = $logContainer
        [System.Windows.Controls.Grid]::SetColumn($btnLog, 2)
        [System.Windows.Controls.Grid]::SetRow($btnLog, 0)

        $btnLog.Add_Click({
            $target = $this.Tag
            if ($null -ne $target) {
                if ($target.Visibility -eq "Visible") {
                    $target.Visibility = "Collapsed"
                    $this.Content = "Show Log"
                } else {
                    $target.Visibility = "Visible"
                    $this.Content = "Hide Log"
                }
            }
        })

        $cardGrid.Children.Add($btnLog) | Out-Null
        $card.Child = $cardGrid
        $SummaryPanel.Children.Add($card) | Out-Null
    }

    $global:isInstallFinished = $true
    $BtnCancelInstall.Content = "Close"
    $BtnCancelInstall.IsEnabled = $true
    if ($BtnExportLog) { $BtnExportLog.Visibility = "Visible" }
}

function Start-AppsInstallation($toInstall, $winControls, [switch]$isUpgradeAll, [string]$Provider = 'winget') {
    $TxtLog = $winControls.TxtLog
    $LblProgressTitle = $winControls.LblProgressTitle
    $LblProgress = $winControls.LblProgress
    $PbInstall = $winControls.PbInstall
    $BtnCancelInstall = $winControls.BtnCancelInstall
    $BtnExportLog = $winControls.BtnExportLog

    $global:isInstallFinished = $false
    $BtnCancelInstall.Content = "Cancel"
    $BtnCancelInstall.IsEnabled = $true
    if ($BtnExportLog) { $BtnExportLog.Visibility = "Collapsed" }
    $LblProgressTitle.Text = if ($isUpgradeAll) { "Updating Outdated Applications..." } else { "Installing Apps..." }
    $PbInstall.IsIndeterminate = $true
    $PbInstall.Visibility = "Visible"

    $installResults = @()
    $count = 0

    foreach ($app in $toInstall) {
        $appLog = ""
        if ($global:cancelInstall) {
            $TxtLog.AppendText("`n[!] Installation Cancelled by User.`n")
            $TxtLog.ScrollToEnd()
            $installResults += @{ App = $app; Code = -1; Cancelled = $true; Log = "" }
            continue
        }

        $pkgProvider = if ($app.Provider) { $app.Provider } else { $Provider }
        $targetId = if ($isUpgradeAll) { $app.Id } else { Get-AppPackageId -App $app -Provider $pkgProvider }
        $provLabel = if ($pkgProvider -eq 'choco') { 'Chocolatey' } else { 'WinGet' }

        $count++
        $LblProgress.Text = if ($isUpgradeAll) { "Running $provLabel Upgrade..." } else { "Installing ($count / $($toInstall.Count)): $($app.Name)" }
        $TxtLog.AppendText("`n---> Starting ($provLabel): $($app.Name)`n")
        $TxtLog.ScrollToEnd()
        Invoke-DoEvents

        if (-not $isUpgradeAll -and -not (Test-SafePackageId $targetId)) {
            $errMsg = if ($pkgProvider -eq 'choco' -and -not $targetId) {
                "$($app.Name) is not available in Chocolatey."
            } else {
                "Invalid package identifier: $targetId"
            }
            $TxtLog.AppendText("[!] $errMsg`n")
            $TxtLog.ScrollToEnd()
            $installResults += @{ App = $app; Code = -1; Cancelled = $false; Log = $errMsg }
            continue
        }

        if ($pkgProvider -eq 'choco') {
            $chocoExe = Get-ChocoExecutable
            if (-not $chocoExe) {
                $errMsg = "Chocolatey executable (choco.exe) not found."
                $TxtLog.AppendText("[!] $errMsg`n")
                $TxtLog.ScrollToEnd()
                $installResults += @{ App = $app; Code = -1; Cancelled = $false; Log = $errMsg }
                continue
            }
            $runnerExe = "`"$chocoExe`""
            $wArgs = if ($isUpgradeAll) { "upgrade all -y --no-progress" } else { "install `"$targetId`" -y --no-progress" }
            $useFallback = $false
        } else {
            $runnerExe = "winget"
            if ($isUpgradeAll) {
                $wArgs = "upgrade --all --silent --disable-interactivity --accept-package-agreements --accept-source-agreements"
            } else {
                $wArgs = "install --exact --id=`"$targetId`" --source=winget --silent --disable-interactivity --accept-package-agreements --accept-source-agreements"
            }
            if ($app.Dep -and $global:depCheckBoxes.ContainsKey($app.Name)) {
                $depChk = $global:depCheckBoxes[$app.Name]
                if (-not $depChk.IsChecked) {
                    $wArgs += " --skip-dependencies"
                }
            }
            $useFallback = ($app.Scope -eq "User" -and $global:isAdmin)
        }

        $finalCode = 0

        $safeId = $targetId -replace '[^a-zA-Z0-9._-]', '_'
        $tmpOut = "$env:TEMP\winget_out_$safeId.log"
        $tmpDone = "$env:TEMP\winget_done_$safeId.log"
        $batPath = "$env:TEMP\winget_run_$safeId.bat"
        $vbsPath = "$env:TEMP\winget_run_$safeId.vbs"

        # Helper to run package manager and stream output without blocking the UI thread
        $runWinget = {
            param([bool]$asUserFallback)

            Remove-Item $tmpOut, $tmpDone, $batPath, $vbsPath -Force -ErrorAction SilentlyContinue

            $batCmd = "@echo off`r`nchcp 65001 > nul`r`n$runnerExe $wArgs > `"$tmpOut`" 2>&1`r`necho %ERRORLEVEL% > `"$tmpDone`""
            [System.IO.File]::WriteAllText($batPath, $batCmd, [System.Text.UTF8Encoding]::new($false))

            $procHandle = $null
            if ($asUserFallback) {
                $vbsCmd = "Set WshShell = CreateObject(`"WScript.Shell`")`r`nWshShell.Run chr(34) & `"$batPath`" & Chr(34), 0`r`nSet WshShell = Nothing"
                [System.IO.File]::WriteAllText($vbsPath, $vbsCmd, [System.Text.Encoding]::Unicode)
                Start-Process "explorer.exe" -ArgumentList "`"$vbsPath`""
            } else {
                $psi = New-Object System.Diagnostics.ProcessStartInfo
                $psi.FileName = "cmd.exe"
                $psi.Arguments = "/c `"$batPath`""
                $psi.CreateNoWindow = $true
                $psi.UseShellExecute = $false
                $procHandle = [System.Diagnostics.Process]::Start($psi)
            }

            $lastPos = 0
            $lastProgressUpdate = [DateTime]::MinValue
            $isDownloading = $false
            $dlTotalBytes = 0
            $procExitedAt = $null
            $fallbackWatch = [System.Diagnostics.Stopwatch]::StartNew()

            $readLogChunk = {
                if (-not (Test-Path $tmpOut)) { return $null }
                $fs = $null
                try {
                    $fs = New-Object System.IO.FileStream($tmpOut, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    if ($fs.Length -gt $lastPos) {
                        $fs.Seek($lastPos, [System.IO.SeekOrigin]::Begin) | Out-Null
                        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8)
                        $text = $sr.ReadToEnd()
                        $lastPos = $fs.Position
                        $sr.Close()
                        if ($text) {
                            $TxtLog.AppendText($text)
                            $script:currentAppLog += $text
                            $TxtLog.ScrollToEnd()
                            try { [Console]::Write($text) } catch { $null = $_ }
                            return $text
                        }
                    }
                } catch { $null = $_ }
                finally {
                    if ($null -ne $fs) { $fs.Dispose() }
                }
                return $null
            }

            while (-not (Test-Path $tmpDone)) {
                if ($global:cancelInstall) {
                    if ($null -ne $procHandle) {
                        try {
                            Start-Process "taskkill.exe" -ArgumentList "/F /T /PID $($procHandle.Id)" -NoNewWindow -Wait -ErrorAction SilentlyContinue
                        } catch { $null = $_ }
                    } else {
                        try {
                            $pattern = if ($isUpgradeAll) { '*upgrade*--all*' } else { "*$($app.Id)*" }
                            Get-CimInstance Win32_Process -Filter "Name='winget.exe'" -ErrorAction SilentlyContinue |
                                Where-Object { $_.CommandLine -like $pattern } |
                                ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
                        } catch { $null = $_ }
                    }
                    break
                }

                # Guard against silent runner crash before $tmpDone is written
                if ($null -ne $procHandle) {
                    if ($procHandle.HasExited) {
                        if ($null -eq $procExitedAt) { $procExitedAt = [DateTime]::UtcNow }
                        elseif (([DateTime]::UtcNow - $procExitedAt).TotalMilliseconds -ge 300) { break }
                    }
                } elseif (-not (Test-Path $tmpOut) -and $fallbackWatch.Elapsed.TotalSeconds -ge 15) {
                    $TxtLog.AppendText("`n[!] Background launcher timed out waiting for output.`n")
                    $TxtLog.ScrollToEnd()
                    break
                }

                $chunk = & $readLogChunk
                if ($chunk) {
                    if ($chunk -match "(?i)Downloading\s+(https?://[^\s]+)") {
                        $isDownloading = $true
                        $dlTotalBytes = 0
                    }

                    if ($chunk -match "(?i)(\d+(?:\.\d+)?)\s*([KMG]B)\s*/\s*(\d+(?:\.\d+)?)\s*([KMG]B)") {
                        $LblProgress.Text = "Installing ($count / $($toInstall.Count)): $($app.Name) - $($matches[0])"
                        $totVal = [double]$matches[3]
                        $totUnit = $matches[4].ToUpper()
                        $mult = switch ($totUnit) { "KB" { 1KB } "GB" { 1GB } default { 1MB } }
                        $dlTotalBytes = [long]($totVal * $mult)
                    } elseif ($chunk -match "(\d+\s*%)") {
                        $LblProgress.Text = "Installing ($count / $($toInstall.Count)): $($app.Name) - $($matches[1])"
                    }

                    if ($chunk -match "(?i)(Successfully verified|Starting package install|Успешно проверен|Установка пакета)") {
                        $isDownloading = $false
                        $PbInstall.IsIndeterminate = $true
                        $LblProgress.Text = if ($isUpgradeAll) { "Running WinGet Upgrade..." } else { "Installing ($count / $($toInstall.Count)): $($app.Name)" }
                    }
                }

                # Update progress bar if downloading (throttled to 250ms)
                if ($isDownloading) {
                    $now = [DateTime]::UtcNow
                    if (($now - $lastProgressUpdate).TotalMilliseconds -ge 250) {
                        $lastProgressUpdate = $now
                        $currBytes = 0
                        try {
                            $newestDir = Get-ChildItem -Path "$env:TEMP\WinGet", "$env:LOCALAPPDATA\Temp\WinGet" -Filter "*$($app.Id)*" -Directory -ErrorAction SilentlyContinue |
                                Sort-Object LastWriteTime -Descending | Select-Object -First 1
                            if ($newestDir) {
                                $dlFiles = Get-ChildItem -Path $newestDir.FullName -File -Recurse -ErrorAction SilentlyContinue
                                if ($dlFiles) {
                                    $currBytes = ($dlFiles | Measure-Object -Property Length -Sum).Sum
                                }
                            }
                        } catch { $null = $_ }

                        if ($currBytes -gt 0) {
                            $currMB = [Math]::Round($currBytes / 1MB, 1)
                            $progStr = "$currMB MB"
                            if ($dlTotalBytes -gt 0) {
                                $totMB = [Math]::Round($dlTotalBytes / 1MB, 1)
                                $pct = [Math]::Min(100, [Math]::Max(0, [Math]::Round(($currBytes / $dlTotalBytes) * 100)))
                                $progStr = "$currMB MB / $totMB MB ($pct%)"
                                $PbInstall.IsIndeterminate = $false
                                $PbInstall.Value = $pct
                            }
                            $LblProgress.Text = "Installing ($count / $($toInstall.Count)): $($app.Name) - $progStr"
                        }
                    }
                }

                Invoke-DoEvents
                Start-Sleep -Milliseconds 50
            }

            $null = & $readLogChunk

            $retCode = -1
            if (Test-Path $tmpDone) {
                try {
                    $retCode = (Get-Content $tmpDone -Raw).Trim() -as [int]
                } catch { $null = $_ }
            } elseif ($null -ne $procHandle -and $procHandle.HasExited) {
                $retCode = $procHandle.ExitCode
            }
            return $retCode
        }

        $script:currentAppLog = ""
        if (-not $useFallback) {
            $finalCode = & $runWinget $false

            if ($script:currentAppLog -match "cannot be run from an administrator context" -and -not $global:cancelInstall) {
                $TxtLog.AppendText("`n[!] Administrator block detected. Retrying as normal user in background...`n")
                $TxtLog.ScrollToEnd()
                Write-Host "Admin block detected for $($app.Name). Retrying via explorer.exe..." -ForegroundColor Yellow
                $useFallback = $true
            }
        }

        if ($useFallback -and -not $global:cancelInstall) {
            $finalCode = & $runWinget $true
        }

        $appLog = $script:currentAppLog

        # Cleanup temporary runner files
        Remove-Item $tmpOut, $tmpDone, $batPath, $vbsPath -Force -ErrorAction SilentlyContinue

        if (-not $global:cancelInstall) {
            # Bundled bloatware cleanup & background downloader eradication (WinGet only, after successful install)
            if ($pkgProvider -eq 'winget' -and $wArgs -match "--skip-dependencies" -and $finalCode -in @(0, 3010, 1641)) {
                if ($app.Name -eq "TeamSpeak 3") {
                    $TxtLog.AppendText("`n[+] Ensuring bundled Overwolf is removed...`n")
                    $TxtLog.ScrollToEnd()
                    Invoke-DoEvents
                    
                    # 1. Kill background NSIS downloader stub and active Overwolf processes
                    Get-Process -Name "Un_A", "Overwolf*", "OWClient*", "OWLauncher*" -ErrorAction SilentlyContinue | Stop-Process -Force
                    
                    # 2. Wipe temporary background extraction directories
                    Remove-Item "$env:TEMP\~nsu*.tmp", "$env:LOCALAPPDATA\Temp\~nsu*.tmp" -Recurse -Force -ErrorAction SilentlyContinue
                    
                    # 3. Clean uninstallation if registered
                    Start-Process "winget" -ArgumentList "uninstall --exact --id Overwolf.Overwolf --silent --accept-source-agreements" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                    if (Test-Path "C:\Program Files (x86)\Overwolf\OWUninstaller.exe") {
                        Start-Process "C:\Program Files (x86)\Overwolf\OWUninstaller.exe" -ArgumentList "/silent" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                    }
                    
                    # 4. Clean leftover persistence directories and registry keys
                    Remove-Item "C:\Program Files (x86)\Overwolf", "$env:LOCALAPPDATA\Overwolf", "$env:APPDATA\Overwolf" -Recurse -Force -ErrorAction SilentlyContinue
                    Remove-Item "HKCU:\Software\OverwolfPersist", "HKLM:\Software\WOW6432Node\OverwolfPersist" -Recurse -Force -ErrorAction SilentlyContinue
                }
                if ($app.Name -eq "MSI Afterburner") {
                    $TxtLog.AppendText("`n[+] Removing bundled RivaTuner...`n")
                    $TxtLog.ScrollToEnd()
                    Invoke-DoEvents
                    Start-Process "winget" -ArgumentList "uninstall --exact --id Guru3D.RTSS --silent --accept-source-agreements" -Wait -NoNewWindow -ErrorAction SilentlyContinue
                }
            }

            $TxtLog.AppendText("`n---> Done: $($app.Name) (Exit Code: $finalCode)`n")
            $TxtLog.ScrollToEnd()
            $installResults += @{ App = $app; Code = $finalCode; Cancelled = $false; Log = $appLog }
            Write-Host "Finished $($app.Name) with code $finalCode" -ForegroundColor Green
            Invoke-DoEvents
        } else {
            $installResults += @{ App = $app; Code = -1; Cancelled = $true; Log = $appLog }
        }
    }

    $summaryTitle = if ($global:cancelInstall) {
        "Installation Aborted"
    } elseif ($isUpgradeAll) {
        "Upgrade Complete"
    } else {
        "Installation Complete"
    }
    Show-InstallSummary -InstallResults $installResults -WinControls $winControls -Title $summaryTitle
}


function Start-SystemUpgrade($winControls, [string]$Provider = 'winget') {
    $provLabel = if ($Provider -eq 'choco') { 'Chocolatey' } else { 'WinGet' }
    $virtualApp = @{
        Name     = "System-wide Application Upgrade ($provLabel)"
        Id       = if ($Provider -eq 'choco') { "Choco.UpgradeAll" } else { "WinGet.UpgradeAll" }
        Cat      = 99
        Sel      = $true
        Provider = $Provider
    }
    Start-AppsInstallation @($virtualApp) $winControls -isUpgradeAll -Provider $Provider
}