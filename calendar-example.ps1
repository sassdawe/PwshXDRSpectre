$calendar = Write-SpectreCalendar -Date (Get-Date) -PassThru
$files = Get-ChildItem | Select-Object Name, LastWriteTime -First 3 | Format-SpectreTable | Format-SpectreAligned -HorizontalAlignment Right -VerticalAlignment Bottom
$panel1 = $files | Format-SpectrePanel -Header "panel 1 (align bottom right)" -Expand -Color Green
$panel2 = "hello row 2" | Format-SpectrePanel -Header "panel 2" -Expand -Color Blue
$panel3 = $calendar | Format-SpectreAligned | Format-SpectrePanel -Header "panel 3 (align middle center)" -Expand -Color Yellow

$row1 = New-SpectreLayout -Name "row1" -Data $panel1 -Ratio 1
$row2 = New-SpectreLayout -Name "row2" -Columns @($panel2, $panel3) -Ratio 2
$root = New-SpectreLayout -Name "root" -Rows @($row1, $row2)

$root | Out-SpectreHost