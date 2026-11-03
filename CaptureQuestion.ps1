param([Parameter(Mandatory=$true)][string]$OutputPath)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class CaptureDpi {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr context);
}
'@
try { if (-not [CaptureDpi]::SetProcessDpiAwarenessContext([IntPtr](-4))) { [void][CaptureDpi]::SetProcessDPIAware() } }
catch { [void][CaptureDpi]::SetProcessDPIAware() }
$captureDir = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'captures'))
$destination = [System.IO.Path]::GetFullPath($OutputPath)
if ([System.IO.Path]::GetDirectoryName($destination) -ine $captureDir -or [System.IO.Path]::GetFileName($destination) -notmatch '^[a-fA-F0-9]{32}\.png$') { throw 'Invalid capture destination' }
[void][System.IO.Directory]::CreateDirectory($captureDir)
$script:selection = $null
$script:origin = $null
$script:captured = $false
$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
$form = New-Object System.Windows.Forms.Form
$form.FormBorderStyle = 'None'
$form.Text = 'Select a question'
$form.StartPosition = 'Manual'
$form.Bounds = $bounds
$form.BackColor = [System.Drawing.Color]::Black
$form.Opacity = 0.30
$form.TopMost = $true
$form.ShowInTaskbar = $true
$form.KeyPreview = $true
$form.Cursor = [System.Windows.Forms.Cursors]::Cross
$form.Add_Shown({ $form.Activate() })
$form.Add_KeyDown({ if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Escape) { $form.Close() } })
$form.Add_MouseDown({ if ($_.Button -eq [System.Windows.Forms.MouseButtons]::Left) { $script:origin = $_.Location; $script:selection = $null } })
$form.Add_MouseMove({
    if ($null -ne $script:origin -and $_.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
        $left = [Math]::Min($script:origin.X, $_.X); $top = [Math]::Min($script:origin.Y, $_.Y)
        $script:selection = [System.Drawing.Rectangle]::new($left, $top, [Math]::Abs($script:origin.X - $_.X), [Math]::Abs($script:origin.Y - $_.Y))
        $form.Invalidate()
    }
})
$form.Add_Paint({
    $brush = [System.Drawing.Brushes]::White
    $_.Graphics.DrawString('Drag to select the question. Esc to cancel.', $form.Font, $brush, 24, 24)
    if ($null -ne $script:selection) { $_.Graphics.DrawRectangle([System.Drawing.Pens]::Lime, $script:selection) }
})
$form.Add_MouseUp({
    if ($_.Button -ne [System.Windows.Forms.MouseButtons]::Left -or $null -eq $script:selection -or $script:selection.Width -lt 20 -or $script:selection.Height -lt 20) { return }
    $form.Hide()
    [System.Windows.Forms.Application]::DoEvents()
    Start-Sleep -Milliseconds 200
    $bitmap = [System.Drawing.Bitmap]::new($script:selection.Width, $script:selection.Height)
    try {
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        try { $graphics.CopyFromScreen($bounds.Left + $script:selection.Left, $bounds.Top + $script:selection.Top, 0, 0, $bitmap.Size) } finally { $graphics.Dispose() }
        $bitmap.Save($destination, [System.Drawing.Imaging.ImageFormat]::Png)
        $script:captured = $true
    } finally { $bitmap.Dispose(); $form.Close() }
})
[System.Windows.Forms.Application]::Run($form)
if ($script:captured) { exit 0 } else { exit 1 }
