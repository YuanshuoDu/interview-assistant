param(
    [string]$AnswerPath = (Join-Path $PSScriptRoot 'current-answer.json'),
    [switch]$ValidateOnly,
    [switch]$ValidateLayout
)

$ErrorActionPreference = 'Stop'

foreach ($name in @('CAREER_CONTEXT', 'INTERVIEW_CONTEXT')) {
    $destination = Join-Path $PSScriptRoot ($name + '.md')
    $example = Join-Path $PSScriptRoot ($name + '.example.md')
    if (-not [System.IO.File]::Exists($destination) -and [System.IO.File]::Exists($example)) {
        [System.IO.File]::Copy($example, $destination, $false)
    }
}

function Read-AnswerFile {
    param([string]$Path)
    $text = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    $data = $text | ConvertFrom-Json
    if ($null -eq $data -or $data -is [System.Array] -or $data.answer -isnot [string] -or [string]::IsNullOrWhiteSpace($data.answer)) {
        throw 'The answer file must contain one object with a non-empty answer string.'
    }
    return [pscustomobject]@{ Text = $text; Data = $data }
}

if (-not [System.IO.File]::Exists($AnswerPath)) {
    [System.IO.File]::WriteAllText($AnswerPath, '{"question":"Welcome","answer":"Connect, then capture a question to generate an answer.","keywords":[]}', [System.Text.UTF8Encoding]::new($false))
}
if (-not [System.IO.File]::Exists((Join-Path $PSScriptRoot 'answer-bank.json'))) {
    [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot 'answer-bank.json'), '[]', [System.Text.UTF8Encoding]::new($false))
}
$initial = Read-AnswerFile -Path $AnswerPath
if ($ValidateOnly) {
    [pscustomobject]@{
        Valid = $true
        AnswerPath = [System.IO.Path]::GetFullPath($AnswerPath)
        AnswerCharacters = ([string]$initial.Data.answer).Length
    } | ConvertTo-Json -Compress
    exit 0
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Interview Assistant"
        Width="880" Height="620" MinWidth="600" MinHeight="400"
        WindowStartupLocation="CenterScreen" Topmost="False" Opacity="1"
        ShowInTaskbar="True" AllowsTransparency="True" WindowStyle="None" ResizeMode="CanResizeWithGrip"
        Background="Transparent" Foreground="#F3F4F6" FontFamily="Segoe UI">
  <Window.Resources>
    <SolidColorBrush x:Key="PanelBackground" Color="#111827" Opacity="0.60"/>
    <Style TargetType="Button">
      <Setter Property="Background" Value="#334155"/>
      <Setter Property="Foreground" Value="#F8FAFC"/>
      <Setter Property="BorderBrush" Value="#64748B"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="Padding" Value="10,5"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="FontSize" Value="12"/>
      <Setter Property="Cursor" Value="Hand"/>
    </Style>
  </Window.Resources>
  <Border x:Name="BackgroundPanel" Background="{StaticResource PanelBackground}" BorderBrush="#9964758B" BorderThickness="1" CornerRadius="12">
  <Grid Margin="18,12,18,12">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <Grid Grid.Row="0" Margin="0,0,0,8">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <StackPanel>
        <StackPanel x:Name="DragHandle" Background="Transparent" Cursor="SizeAll" ToolTip="Drag to move · Alt+Tab switches windows">
          <TextBlock Text="INTERVIEW ASSISTANT" Foreground="#93C5FD" FontSize="12" FontWeight="SemiBold"/>
          <TextBlock x:Name="ContextLabel" Text="Interview context" Foreground="#CBD5E1" FontSize="11" Margin="0,3,0,0"/>
        </StackPanel>
      </StackPanel>
      <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
        <Button x:Name="SignInButton" Content="Sign in" ToolTip="Sign in through the Codex CLI"/>
        <Button x:Name="ContextButton" Content="Interview context" ToolTip="Edit the current employer and role"/>
        <Button x:Name="CareerButton" Content="Career facts" ToolTip="Edit the experience used to draft answers"/>
        <CheckBox x:Name="HighlightToggle" Content="Highlight" IsChecked="False" Foreground="#F8FAFC" VerticalAlignment="Center" Margin="0,0,8,0"/>
        <Button x:Name="FontSmaller" Content="A−" ToolTip="Smaller answer text"/>
        <Button x:Name="FontLarger" Content="A+" ToolTip="Larger answer text"/>
        <Button x:Name="MinimizeButton" Content="−" ToolTip="Minimize"/>
        <Button x:Name="CloseButton" Content="×" ToolTip="Close" Margin="0"/>
      </StackPanel>
    </Grid>
    <Grid Grid.Row="1" Margin="0,0,0,10">
      <Grid.ColumnDefinitions><ColumnDefinition Width="Auto"/><ColumnDefinition Width="Auto"/><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
      <Button x:Name="MonitorButton" Content="Connect" Background="#2563EB" FontSize="14" FontWeight="SemiBold" MinWidth="100" Padding="14,7"/>
      <Button x:Name="CaptureButton" Grid.Column="1" Content="Capture question" FontSize="14" FontWeight="SemiBold" Padding="14,7"/>
      <TextBlock x:Name="MonitorStateText" Grid.Column="2" Text="Not connected" FontSize="12" Foreground="#CBD5E1" VerticalAlignment="Center" Margin="5,0,8,0" TextTrimming="CharacterEllipsis"/>
      <TextBlock x:Name="NavigationText" Grid.Column="3" Text="Previous / Next" FontSize="11" Foreground="#A7F3D0" VerticalAlignment="Center"/>
    </Grid>
    <TextBlock x:Name="QuestionText" Grid.Row="2" TextWrapping="Wrap" FontSize="17" FontWeight="SemiBold" Foreground="#E0F2FE" Margin="0,0,0,9"/>
    <Border x:Name="AnswerCard" Grid.Row="3" Background="Transparent" BorderBrush="#7764758B" BorderThickness="1" CornerRadius="8" Padding="12,10">
      <Viewbox x:Name="AnswerViewbox" Stretch="Uniform" StretchDirection="DownOnly" HorizontalAlignment="Left" VerticalAlignment="Top">
        <TextBlock x:Name="AnswerText" Width="800" TextWrapping="Wrap" FontSize="18" LineHeight="26.64" Foreground="#FFFFFF"/>
      </Viewbox>
    </Border>
    <TextBlock x:Name="KeywordsText" Grid.Row="4" TextWrapping="Wrap" FontSize="13" Foreground="#A7F3D0" Margin="0,8,0,8"/>
    <Grid Grid.Row="5">
      <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
      <Grid Grid.Row="0">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock x:Name="TimerText" Text="1:00" FontSize="22" FontWeight="SemiBold" Width="61" VerticalAlignment="Center" Foreground="#FDE68A"/>
          <Button x:Name="TimerButton" Content="Start 60s"/>
          <Button x:Name="ResetButton" Content="Reset"/>
        </StackPanel>
        <StackPanel Grid.Column="2" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="Transparency" Foreground="#CBD5E1" FontSize="12" VerticalAlignment="Center" Margin="0,0,7,0"/>
          <Slider x:Name="OpacitySlider" Minimum="0.05" Maximum="0.90" Value="0.40" Width="104" VerticalAlignment="Center" SmallChange="0.05" LargeChange="0.1"/>
          <TextBlock x:Name="OpacityText" Text="40%" Foreground="#CBD5E1" Width="38" TextAlignment="Right" VerticalAlignment="Center"/>
        </StackPanel>
      </Grid>
      <TextBlock x:Name="StatusText" Grid.Row="1" TextWrapping="Wrap" Foreground="#CBD5E1" FontSize="10" Margin="0,7,0,0" Text="Local notes · Alt+Tab switches windows · Text fits automatically"/>
    </Grid>
  </Grid>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$script:window = [Windows.Markup.XamlReader]::Load($reader)
$script:questionText = $window.FindName('QuestionText')
$script:answerText = $window.FindName('AnswerText')
$script:keywordsText = $window.FindName('KeywordsText')
$script:answerViewbox = $window.FindName('AnswerViewbox')
$script:answerCard = $window.FindName('AnswerCard')
$script:panelBackground = $window.Resources['PanelBackground'].CloneCurrentValue()
$window.Resources['PanelBackground'] = $panelBackground
$window.FindName('BackgroundPanel').Background = $panelBackground
$script:statusText = $window.FindName('StatusText')
$script:timerText = $window.FindName('TimerText')
$script:timerButton = $window.FindName('TimerButton')
$script:opacityText = $window.FindName('OpacityText')
$script:navigationText = $window.FindName('NavigationText')
$script:monitorButton = $window.FindName('MonitorButton')
$script:monitorStateText = $window.FindName('MonitorStateText')
$script:contextLabel = $window.FindName('ContextLabel')
$script:highlightEnabled = $false
$script:settingsPath = Join-Path $PSScriptRoot 'settings.json'
try { $savedSettings = [System.IO.File]::ReadAllText($script:settingsPath) | ConvertFrom-Json; $script:highlightEnabled = ($savedSettings.highlight -eq $true) } catch { }
$window.FindName('HighlightToggle').IsChecked = $script:highlightEnabled
$script:contextPath = Join-Path $PSScriptRoot 'INTERVIEW_CONTEXT.md'
$script:bankPath = Join-Path $PSScriptRoot 'answer-bank.json'
$script:monitorControlPath = Join-Path $PSScriptRoot 'monitor-control.json'
$script:monitorStatusPath = Join-Path $PSScriptRoot 'monitor-status.json'
$script:manualRequestPath = Join-Path $PSScriptRoot 'manual-question.json'
$script:manualResultPath = Join-Path $PSScriptRoot 'manual-result.json'
$script:manualGenerationId = $null
$script:lastManualResultId = $null
$script:lastBankText = $null
$script:savedAnswers = @()
$script:bankIndex = -1
$script:displayedData = $null
$script:monitorEnabled = $false
$script:monitorRequestId = [Guid]::NewGuid().ToString('N')
$script:monitorConnectedOnce = $false
$script:monitorRequestedOnce = $false
$script:statusOverrideUntil = [DateTimeOffset]::MinValue
$script:clock = [System.Diagnostics.Stopwatch]::new()
$script:lastText = $null
$script:stopping = $false

function Reset-PracticeTimer {
    $script:clock.Reset()
    $script:timerText.Text = '1:00'
    $script:timerText.Foreground = [Windows.Media.Brushes]::Khaki
    $script:timerButton.Content = 'Start 60s'
}

function Update-InterviewContextLabel {
    try {
        $firstLine = @([System.IO.File]::ReadAllLines($script:contextPath, [System.Text.Encoding]::UTF8) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) | Select-Object -First 1
        if ([string]::IsNullOrWhiteSpace($firstLine)) { $firstLine = 'Not set' }
        $script:contextLabel.Text = 'Current interview: ' + $firstLine.Trim()
    } catch { $script:contextLabel.Text = 'Current interview: Not set' }
}

function Write-AtomicJson {
    param([string]$Path, $Data)
    $text = ConvertTo-Json -InputObject $Data -Depth 12
    $temporaryPath = $Path + '.' + [Guid]::NewGuid().ToString('N') + '.tmp'
    $backupPath = $temporaryPath + '.old'
    try {
        [System.IO.File]::WriteAllText($temporaryPath, $text, [System.Text.UTF8Encoding]::new($false))
        if ([System.IO.File]::Exists($Path)) { [System.IO.File]::Replace($temporaryPath, $Path, $backupPath) }
        else { [System.IO.File]::Move($temporaryPath, $Path) }
    }
    finally {
        if ([System.IO.File]::Exists($temporaryPath)) { [System.IO.File]::Delete($temporaryPath) }
        if ([System.IO.File]::Exists($backupPath)) { [System.IO.File]::Delete($backupPath) }
    }
    return $text
}

function Get-AnswerHeading {
    param($Data)
    $heading = [string]$Data.question
    if ([string]::IsNullOrWhiteSpace($heading)) { $heading = [string]$Data.title }
    if ([string]::IsNullOrWhiteSpace($heading)) { $heading = 'Practice answer' }
    return $heading
}

function Sync-BankIndex {
    $script:bankIndex = -1
    for ($i = 0; $i -lt $script:savedAnswers.Count; $i++) {
        if ([string]::Equals((Get-AnswerHeading $script:savedAnswers[$i]), (Get-AnswerHeading $script:displayedData), [StringComparison]::Ordinal) -and
            [string]::Equals([string]$script:savedAnswers[$i].answer, [string]$script:displayedData.answer, [StringComparison]::Ordinal)) {
            $script:bankIndex = $i
            break
        }
    }
    if ($script:savedAnswers.Count -eq 0) { $script:navigationText.Text = 'No saved answers' }
    elseif ($script:bankIndex -ge 0) {
        $script:navigationText.Text = 'Previous  ' + ($script:bankIndex + 1) + '/' + $script:savedAnswers.Count + '  Next'
    }
    else { $script:navigationText.Text = 'Previous  Current / ' + $script:savedAnswers.Count + '  Next' }
}

function Set-AnswerHighlights {
    param([string]$Answer, $Keywords)
    if (-not $script:highlightEnabled) { $script:answerText.Text = $Answer; return }
    # Saved keywords may be compact notes separated by middle dots or labels.
    # Only highlight exact, whole-word occurrences actually present in the answer.
    $candidates = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($item in @($Keywords)) {
        if ($null -eq $item) { continue }
        $value = ([string]$item).Trim()
        if ($value.Length -gt 1 -and $value.Length -le 100) { [void]$candidates.Add($value) }
        foreach ($part in ($value -split '[·→:]')) {
            $part = $part.Trim()
            if ($part.Length -gt 1 -and $part.Length -le 100) { [void]$candidates.Add($part) }
        }
    }
    $spans = [System.Collections.Generic.List[object]]::new()
    foreach ($candidate in @($candidates | Sort-Object Length -Descending)) {
        $pattern = '(?<![\p{L}\p{N}_])' + [regex]::Escape($candidate) + '(?![\p{L}\p{N}_])'
        foreach ($match in [regex]::Matches($Answer, $pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)) {
            $overlap = $false
            foreach ($span in $spans) {
                if ($match.Index -lt ($span.Start + $span.Length) -and ($match.Index + $match.Length) -gt $span.Start) { $overlap = $true; break }
            }
            if (-not $overlap) { $spans.Add([pscustomobject]@{ Start = $match.Index; Length = $match.Length }) }
        }
    }
    $script:answerText.Inlines.Clear()
    $cursor = 0
    foreach ($span in @($spans | Sort-Object Start)) {
        if ($span.Start -gt $cursor) { $script:answerText.Inlines.Add([Windows.Documents.Run]::new($Answer.Substring($cursor, $span.Start - $cursor))) }
        $run = [Windows.Documents.Run]::new($Answer.Substring($span.Start, $span.Length))
        $run.Foreground = [Windows.Media.BrushConverter]::new().ConvertFromString('#FCD34D')
        $run.FontWeight = [Windows.FontWeights]::SemiBold
        $script:answerText.Inlines.Add($run)
        $cursor = $span.Start + $span.Length
    }
    if ($cursor -lt $Answer.Length) { $script:answerText.Inlines.Add([Windows.Documents.Run]::new($Answer.Substring($cursor))) }
}

function Set-DisplayedAnswer {
    param($Loaded)
    $data = $Loaded.Data
    $script:displayedData = $data
    $script:questionText.Text = Get-AnswerHeading $data
    Set-AnswerHighlights -Answer ([string]$data.answer) -Keywords $data.keywords
    $script:keywordsText.Text = @($data.keywords) -join '  ·  '
    $script:lastText = $Loaded.Text
    Sync-BankIndex
    $script:statusText.Text = 'Updated ' + (Get-Date -Format 'HH:mm:ss') + ' - Alt+Tab switches windows'
    Reset-PracticeTimer
}

function Update-AnswerBank {
    if (-not [System.IO.File]::Exists($script:bankPath)) { return }
    $bankText = [System.IO.File]::ReadAllText($script:bankPath, [System.Text.Encoding]::UTF8)
    if ($bankText -ceq $script:lastBankText) { return }
    $bank = $bankText | ConvertFrom-Json
    if ($null -eq $bank) { $bank = @() }
    elseif ($bank -isnot [System.Array]) { $bank = @($bank) }
    foreach ($entry in $bank) {
        if ($null -eq $entry -or $entry -is [System.Array] -or $entry.answer -isnot [string] -or [string]::IsNullOrWhiteSpace($entry.answer)) {
            throw 'Every answer-bank entry must be one object with a non-empty answer string.'
        }
    }
    $script:savedAnswers = $bank
    $script:lastBankText = $bankText
    Sync-BankIndex
}

function Move-SavedAnswer {
    param([int]$Delta)
    if ($script:savedAnswers.Count -eq 0) { return }
    if ($script:bankIndex -lt 0) {
        if ($Delta -lt 0) { $nextIndex = $script:savedAnswers.Count - 1 }
        else { $nextIndex = 0 }
    }
    else { $nextIndex = (($script:bankIndex + $Delta) % $script:savedAnswers.Count + $script:savedAnswers.Count) % $script:savedAnswers.Count }
    $data = $script:savedAnswers[$nextIndex]
    $text = Write-AtomicJson -Path $AnswerPath -Data $data
    Set-DisplayedAnswer -Loaded ([pscustomobject]@{ Text = $text; Data = $data })
}

function Set-MonitorEnabled {
    param([bool]$Enabled)
    $requestId = $script:monitorRequestId
    if ($Enabled -and -not $script:monitorEnabled) { $requestId = [Guid]::NewGuid().ToString('N') }
    [void](Write-AtomicJson -Path $script:monitorControlPath -Data ([ordered]@{
        enabled = $Enabled
        request_id = $requestId
        requested_on = [DateTimeOffset]::UtcNow.ToString('o')
    }))
    $script:monitorRequestId = $requestId
    $script:monitorEnabled = $Enabled
    $script:monitorConnectedOnce = $false
    if ($Enabled) {
        $script:monitorRequestedOnce = $true
        $script:monitorButton.Content = 'Disconnect'
        $script:monitorButton.Background = [Windows.Media.Brushes]::DarkOrange
        $script:monitorStateText.Text = 'Please wait'
    }
    else {
        $script:monitorButton.Content = 'Connect'
        $script:monitorButton.Background = [Windows.Media.Brushes]::DodgerBlue
        if ($script:monitorRequestedOnce) { $script:monitorStateText.Text = 'Disconnected' }
        else { $script:monitorStateText.Text = 'Not connected' }
    }
}

function Update-MonitorStatus {
    if (-not $script:monitorEnabled) { return }
    if ([DateTimeOffset]::UtcNow -lt $script:statusOverrideUntil) { return }
    try {
        if (-not [System.IO.File]::Exists($script:monitorStatusPath)) { throw 'No status yet' }
        $status = [System.IO.File]::ReadAllText($script:monitorStatusPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
        if ([string]$status.request_id -cne $script:monitorRequestId) { throw 'Waiting for matching request' }
        $heartbeat = [DateTimeOffset]::Parse([string]$status.heartbeat_utc, [Globalization.CultureInfo]::InvariantCulture)
        $age = ([DateTimeOffset]::UtcNow - $heartbeat.ToUniversalTime()).TotalSeconds
        if ($age -ge 20 -or $age -lt -3) {
            $script:monitorStateText.Text = 'Connection interrupted'
            return
        }
        $script:monitorConnectedOnce = $true
        $message = [string]$status.status_text
        if ([string]::IsNullOrWhiteSpace($message)) { $message = 'Connected' }
        $script:monitorStateText.Text = $message
        $script:monitorStateText.ToolTip = $message
    }
    catch {
        if ($script:monitorConnectedOnce) { $script:monitorStateText.Text = 'Connection interrupted' }
        else { $script:monitorStateText.Text = 'Waiting for connection' }
    }
}

Set-DisplayedAnswer -Loaded $initial
Update-AnswerBank

$monitorButton.Add_Click({
    try {
        Set-MonitorEnabled -Enabled (-not $script:monitorEnabled)
        if ($script:monitorEnabled -and -not $ValidateLayout) {
            $python = (Get-Command pythonw.exe -ErrorAction Stop).Source
            $worker = Join-Path $PSScriptRoot 'worker.py'
            Start-Process -FilePath $python -ArgumentList @('"' + $worker + '"', $script:monitorRequestId) -WindowStyle Hidden | Out-Null
            $script:monitorStateText.Text = 'Connecting...'
        }
    }
    catch {
        try { Set-MonitorEnabled -Enabled $false } catch { }
        $script:monitorStateText.Text = 'Could not start Python worker'
    }
})
$window.FindName('CaptureButton').Add_Click({
    $imagePath = $null
    $handedOff = $false
    try {
        if (-not $script:monitorEnabled) {
            $script:monitorButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
            if (-not $script:monitorEnabled) { return }
        }
        $captureDir = Join-Path $PSScriptRoot 'captures'
        [void][System.IO.Directory]::CreateDirectory($captureDir)
        $oldImagePath = $null
        try {
            $prior = [System.IO.File]::ReadAllText($script:manualRequestPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($prior.session_id -ceq $script:monitorRequestId -and [string]$prior.generation_id -cmatch '^[0-9a-f]{32}$') {
                $oldImagePath = Join-Path $captureDir ([string]$prior.generation_id + '.png')
            }
        } catch { }
        $script:manualGenerationId = $null
        [void](Write-AtomicJson -Path $script:manualRequestPath -Data ([ordered]@{
            session_id = $script:monitorRequestId; generation_id = $null
        }))
        if ($oldImagePath -and [System.IO.File]::Exists($oldImagePath)) {
            try { [System.IO.File]::Delete($oldImagePath) } catch { }
        }
        $generation = [Guid]::NewGuid().ToString('N')
        $imagePath = Join-Path $captureDir ($generation + '.png')
        $selector = Join-Path $PSScriptRoot 'CaptureQuestion.ps1'
        $script:window.WindowState = 'Minimized'
        try {
            $selectorProcess = Start-Process -FilePath 'powershell.exe' -ArgumentList @('-NoProfile', '-Sta', '-File', ('"' + $selector + '"'), '-OutputPath', ('"' + $imagePath + '"')) -WindowStyle Hidden -Wait -PassThru
        }
        finally { $script:window.WindowState = 'Normal'; [void]$script:window.Activate() }
        if ($selectorProcess.ExitCode -eq 0 -and [System.IO.File]::Exists($imagePath) -and $script:monitorEnabled) {
            $script:manualGenerationId = $generation
            [void](Write-AtomicJson -Path $script:manualRequestPath -Data ([ordered]@{
                session_id = $script:monitorRequestId; generation_id = $generation; image_path = $imagePath
            }))
            $handedOff = $true
            $script:monitorStateText.Text = 'Screenshot received'
        } else {
            $script:monitorStateText.Text = 'Capture cancelled or failed'
            $script:statusOverrideUntil = [DateTimeOffset]::UtcNow.AddSeconds(8)
        }
    }
    catch {
        $script:monitorStateText.Text = 'Capture failed'
        $script:statusOverrideUntil = [DateTimeOffset]::UtcNow.AddSeconds(8)
    }
    finally {
        if (-not $handedOff -and $imagePath -and [System.IO.File]::Exists($imagePath)) {
            try { [System.IO.File]::Delete($imagePath) } catch { }
        }
    }
})
$window.Add_PreviewKeyDown({
    param($sender, $eventArgs)
    try {
        if ($eventArgs.Key -eq [System.Windows.Input.Key]::Left) {
            Move-SavedAnswer -Delta -1
            $eventArgs.Handled = $true
        }
        elseif ($eventArgs.Key -eq [System.Windows.Input.Key]::Right) {
            Move-SavedAnswer -Delta 1
            $eventArgs.Handled = $true
        }
    }
    catch { $script:statusText.Text = 'Could not switch the saved answer; the current answer remains available.' }
})

$window.FindName('HighlightToggle').Add_Click({
    $script:highlightEnabled = ($window.FindName('HighlightToggle').IsChecked -eq $true)
    try { [void](Write-AtomicJson -Path $script:settingsPath -Data @{ highlight = $script:highlightEnabled }) } catch { }
    if ($script:displayedData) { Set-AnswerHighlights -Answer ([string]$script:displayedData.answer) -Keywords $script:displayedData.keywords }
})
$window.FindName('SignInButton').Add_Click({
    try {
        if (-not (Get-Command codex -ErrorAction SilentlyContinue)) { throw 'Codex CLI not found' }
        Start-Process -FilePath 'cmd.exe' -ArgumentList '/k', 'codex login' | Out-Null
        $script:monitorStateText.Text = 'Complete sign-in in the opened terminal'
    } catch { $script:monitorStateText.Text = 'Codex CLI not found; see README' }
})
$window.FindName('CareerButton').Add_Click({
    try { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + (Join-Path $PSScriptRoot 'CAREER_CONTEXT.md') + '"') | Out-Null }
    catch { $script:monitorStateText.Text = 'Unable to open career facts' }
})
$window.FindName('CloseButton').Add_Click({ $script:window.Close() })
$window.FindName('ContextButton').Add_Click({
    try { Start-Process -FilePath 'notepad.exe' -ArgumentList ('"' + $script:contextPath + '"') | Out-Null }
    catch { $script:monitorStateText.Text = 'Unable to open interview context' }
})
$window.FindName('MinimizeButton').Add_Click({ $script:window.WindowState = 'Minimized' })
$window.FindName('DragHandle').Add_MouseLeftButtonDown({
    param($sender, $eventArgs)
    if ($eventArgs.LeftButton -eq [System.Windows.Input.MouseButtonState]::Pressed) {
        $script:window.DragMove()
    }
})
$answerCard.Add_SizeChanged({
    $availableWidth = [Math]::Max(200, $script:answerCard.ActualWidth - 26)
    if ([Math]::Abs($script:answerText.Width - $availableWidth) -gt 1) {
        $script:answerText.Width = $availableWidth
    }
})
$window.FindName('FontSmaller').Add_Click({
    $script:answerText.FontSize = [Math]::Max(12, $script:answerText.FontSize - 1)
    $script:answerText.LineHeight = [Math]::Round($script:answerText.FontSize * 1.48, 2)
})
$window.FindName('FontLarger').Add_Click({
    $script:answerText.FontSize = [Math]::Min(32, $script:answerText.FontSize + 1)
    $script:answerText.LineHeight = [Math]::Round($script:answerText.FontSize * 1.48, 2)
})
$window.FindName('OpacitySlider').Add_ValueChanged({
    param($sender, $eventArgs)
    $script:panelBackground.Opacity = 1 - [double]$sender.Value
    $script:opacityText.Text = [string][Math]::Round($sender.Value * 100) + '%'
})
$window.FindName('ResetButton').Add_Click({ Reset-PracticeTimer })
$timerButton.Add_Click({
    if ($script:clock.IsRunning) {
        $script:clock.Stop()
        $script:timerButton.Content = 'Resume'
    }
    else {
        if ($script:clock.Elapsed.TotalSeconds -ge 60) { Reset-PracticeTimer }
        $script:clock.Start()
        $script:timerButton.Content = 'Pause'
    }
})

$script:uiTimer = New-Object Windows.Threading.DispatcherTimer
$uiTimer.Interval = [TimeSpan]::FromMilliseconds(200)
$uiTimer.Add_Tick({
    if ($script:clock.IsRunning) {
        $remaining = [Math]::Max(0, 60 - [Math]::Floor($script:clock.Elapsed.TotalSeconds))
        $script:timerText.Text = '{0}:{1:00}' -f [Math]::Floor($remaining / 60), ($remaining % 60)
        if ($remaining -le 10) { $script:timerText.Foreground = [Windows.Media.Brushes]::Salmon }
        if ($remaining -le 0) {
            $script:clock.Stop()
            $script:timerButton.Content = 'Restart 60s'
        }
    }
})

$script:fileTimer = New-Object Windows.Threading.DispatcherTimer
$fileTimer.Interval = [TimeSpan]::FromMilliseconds(600)
$fileTimer.Add_Tick({
    Update-InterviewContextLabel
    try {
        $loaded = Read-AnswerFile -Path $AnswerPath
        if ($loaded.Text -cne $script:lastText) { Set-DisplayedAnswer -Loaded $loaded }
        Update-AnswerBank
    }
    catch {
        $script:statusText.Text = 'Waiting for a valid local answer file; keeping the last displayed answer.'
    }
    Update-MonitorStatus
    try {
        if ($script:monitorEnabled -and $script:manualGenerationId -and [System.IO.File]::Exists($script:manualResultPath)) {
            $result = [System.IO.File]::ReadAllText($script:manualResultPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
            if ($result.session_id -ceq $script:monitorRequestId -and $result.generation_id -ceq $script:manualGenerationId -and
                $result.generation_id -cne $script:lastManualResultId -and -not [string]::IsNullOrWhiteSpace([string]$result.answer)) {
                Update-AnswerBank
                $updatedBank = @($script:savedAnswers) + @($result)
                [void](Write-AtomicJson -Path $script:bankPath -Data $updatedBank)
                Update-AnswerBank
                $text = Write-AtomicJson -Path $AnswerPath -Data $result
                Set-DisplayedAnswer -Loaded ([pscustomobject]@{ Text = $text; Data = $result })
                $script:lastManualResultId = [string]$result.generation_id
            }
        }
    } catch { $script:statusText.Text = 'Unable to display result; previous answer retained.' }
})
$window.Add_Closed({
    $script:stopping = $true
    $script:fileTimer.Stop()
    $script:uiTimer.Stop()
    $script:clock.Stop()
    if (-not $ValidateLayout) {
        try { Set-MonitorEnabled -Enabled $false } catch { }
    }
})
if ($ValidateLayout) {
    $validationDirectory = Join-Path ([System.IO.Path]::GetTempPath()) ('interview-notes-validation-' + [Guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($validationDirectory)
    $AnswerPath = Join-Path $validationDirectory 'current-answer.json'
    $script:monitorControlPath = Join-Path $validationDirectory 'monitor-control.json'
    $script:monitorStatusPath = Join-Path $validationDirectory 'monitor-status.json'
    $script:monitorButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    $startControl = [System.IO.File]::ReadAllText($script:monitorControlPath) | ConvertFrom-Json
    Update-MonitorStatus
    $waitingPassed = ($monitorStateText.Text -eq 'Waiting for connection')
    $freshStatus = [ordered]@{ request_id = $script:monitorRequestId; state = 'ready'; status_text = 'Test connected'; heartbeat_utc = [DateTimeOffset]::UtcNow.ToString('o') }
    [void](Write-AtomicJson -Path $script:monitorStatusPath -Data $freshStatus)
    Update-MonitorStatus
    $freshPassed = ($monitorStateText.Text -eq 'Test connected')
    $freshStatus.heartbeat_utc = [DateTimeOffset]::UtcNow.AddSeconds(-21).ToString('o')
    [void](Write-AtomicJson -Path $script:monitorStatusPath -Data $freshStatus)
    Update-MonitorStatus
    $stalePassed = ($monitorStateText.Text -eq 'Connection interrupted')
    $script:monitorButton.RaiseEvent([System.Windows.RoutedEventArgs]::new([System.Windows.Controls.Button]::ClickEvent))
    $stopControl = [System.IO.File]::ReadAllText($script:monitorControlPath) | ConvertFrom-Json
    $script:highlightEnabled = $false
    Set-AnswerHighlights -Answer 'A test phrase.' -Keywords @('test phrase')
    $highlightOffPassed = ($answerText.Text -ceq 'A test phrase.' -and @($answerText.Inlines | Where-Object { $_.Foreground -and $_.Foreground.ToString() -eq '#FFFCD34D' }).Count -eq 0)
    $script:highlightEnabled = $true
    $script:savedAnswers = @([pscustomobject]@{question='Example';answer='I worked with a team to solve a problem.';keywords=@('team')},[pscustomobject]@{question='Example 2';answer='I reviewed the work and learned from feedback.';keywords=@('feedback')})
    Set-DisplayedAnswer -Loaded ([pscustomobject]@{ Text = ''; Data = $script:savedAnswers[0] })
    Move-SavedAnswer -Delta 1
    $rightPassed = ($script:bankIndex -eq 1 -and (Read-AnswerFile -Path $AnswerPath).Data.answer -ceq $script:savedAnswers[1].answer)
    Move-SavedAnswer -Delta -1
    $leftPassed = ($script:bankIndex -eq 0)
    Move-SavedAnswer -Delta -1
    $wrapPassed = ($script:bankIndex -eq $script:savedAnswers.Count - 1)
    Set-DisplayedAnswer -Loaded ([pscustomobject]@{ Text = ''; Data = [pscustomobject]@{ question = 'Validation live question'; answer = 'Validation live answer' } })
    $liveUnknownPassed = ($script:bankIndex -eq -1)
    Move-SavedAnswer -Delta 1
    $liveNextPassed = ($script:bankIndex -eq 0)
    $testAnswer = 'Cyber Security and cyber security; insecurity.'
    Set-AnswerHighlights -Answer $testAnswer -Keywords @('security', 'Cyber Security', 'not present')
    $testHighlighted = @($answerText.Inlines | Where-Object { $_.Foreground -and $_.Foreground.ToString() -eq '#FFFCD34D' })
    $highlightMatchingPassed = ($testHighlighted.Count -eq 2 -and $testHighlighted[0].Text -ceq 'Cyber Security' -and $testHighlighted[1].Text -ceq 'cyber security' -and ((@($answerText.Inlines | ForEach-Object { $_.Text }) -join '') -ceq $testAnswer))
    Set-AnswerHighlights -Answer 'No matching term.' -Keywords @('absent')
    $highlightFallbackPassed = (@($answerText.Inlines | Where-Object { $_.Foreground -and $_.Foreground.ToString() -eq '#FFFCD34D' }).Count -eq 0 -and ((@($answerText.Inlines | ForEach-Object { $_.Text }) -join '') -ceq 'No matching term.'))
    $interactiveResults = [pscustomobject]@{
        StartButtonWritesEnabled = ($startControl.enabled -eq $true -and -not [string]::IsNullOrWhiteSpace($startControl.request_id))
        StopButtonWritesDisabled = ($stopControl.enabled -eq $false -and $stopControl.request_id -ceq $startControl.request_id)
        WaitingUntilConnected = $waitingPassed
        FreshMatchingHeartbeatAccepted = $freshPassed
        StaleHeartbeatNeverTracks = $stalePassed
        RightSelectsOneAnswer = $rightPassed
        LeftSelectsPrevious = $leftPassed
        LeftWrapsToLast = $wrapPassed
        UnknownLiveAnswerHasNoFalseIndex = $liveUnknownPassed
        RightFromLiveSelectsFirst = $liveNextPassed
        HighlightMatching = $highlightMatchingPassed
        HighlightOffPreservesText = $highlightOffPassed
        HighlightNoMatchPreservesText = $highlightFallbackPassed
        ProductionFilesNotWritten = $true
    }
    $panelBackground.Opacity = 0.30
    $brushMutationPassed = ($window.FindName('BackgroundPanel').Background.Opacity -eq 0.30)
    $panelBackground.Opacity = 0.60
    $validationBank = $script:savedAnswers
    if ($validationBank -isnot [System.Array]) { $validationBank = @($validationBank) }
    $layoutResults = @()
    foreach ($testSize in @([System.Windows.Size]::new(880, 620), [System.Windows.Size]::new(600, 400))) {
        foreach ($validationEntry in $validationBank) {
            Set-DisplayedAnswer -Loaded ([pscustomobject]@{ Text = ''; Data = $validationEntry })
            $window.Content.Measure($testSize)
            $window.Content.Arrange([System.Windows.Rect]::new([System.Windows.Point]::new(0, 0), $testSize))
            $window.Content.UpdateLayout()
            $answerBounds = $answerText.TransformToAncestor($answerViewbox).TransformBounds(
                [System.Windows.Rect]::new(0, 0, $answerText.ActualWidth, $answerText.ActualHeight))
            $cardWidth = [Math]::Max(0, $answerCard.ActualWidth - 26)
            $cardHeight = [Math]::Max(0, $answerCard.ActualHeight - 22)
            $layoutResults += [pscustomobject]@{
                Question = $validationEntry.question
                WindowSize = $testSize.ToString()
                FullAnswerFits = ($answerBounds.Width -le $cardWidth + 1 -and $answerBounds.Height -le $cardHeight + 1 -and $answerViewbox.ActualHeight -le $cardHeight + 1)
                HighlightRunCount = @($answerText.Inlines | Where-Object { $_.Foreground -and $_.Foreground.ToString() -eq '#FFFCD34D' }).Count
                AnswerTextPreserved = ((@($answerText.Inlines | ForEach-Object { $_.Text }) -join '') -ceq [string]$validationEntry.answer)
                AnswerBounds = $answerBounds.ToString()
                CardAvailableWidth = $cardWidth
                CardAvailableHeight = $cardHeight
                ViewboxActualHeight = $answerViewbox.ActualHeight
                BaseFontSize = $answerText.FontSize
            }
        }
    }
    [pscustomobject]@{
        XamlLoaded = $true
        WindowShown = $window.IsVisible
        AllowsTransparency = $window.AllowsTransparency
        WindowOpacity = $window.Opacity
        BackgroundOpacity = $panelBackground.Opacity
        TextOpacity = $answerText.Opacity
        BrushFrozen = $panelBackground.IsFrozen
        BrushMutationPassed = $brushMutationPassed
        Topmost = $window.Topmost
        ShowInTaskbar = $window.ShowInTaskbar
        SavedAnswerCount = $script:savedAnswers.Count
        ComboBoxCount = @($xaml.SelectNodes('//*[local-name()="ComboBox"]')).Count
        ScrollViewerCount = @($xaml.SelectNodes('//*[local-name()="ScrollViewer"]')).Count
        InteractiveControls = $interactiveResults
        Layout = $layoutResults
    } | ConvertTo-Json -Depth 6
    $window.Close()
    foreach ($validationFile in [System.IO.Directory]::GetFiles($validationDirectory)) { [System.IO.File]::Delete($validationFile) }
    [System.IO.Directory]::Delete($validationDirectory)
    exit 0
}
try { Set-MonitorEnabled -Enabled $false }
    catch { $script:monitorStateText.Text = 'Unable to open interview context' }
$uiTimer.Start()
$fileTimer.Start()
[void]$window.ShowDialog()
