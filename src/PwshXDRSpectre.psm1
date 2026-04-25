$moduleRoot = Split-Path -Parent $PSCommandPath

$privateFiles = Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Private') -Filter '*.ps1' -ErrorAction SilentlyContinue
foreach ($file in $privateFiles) {
    . $file.FullName
}

$publicFiles = Get-ChildItem -Path (Join-Path -Path $moduleRoot -ChildPath 'Public') -Filter '*.ps1' -ErrorAction SilentlyContinue
foreach ($file in $publicFiles) {
    . $file.FullName
}

$publicFunctionNames = $publicFiles.BaseName
if ($publicFunctionNames) {
    Export-ModuleMember -Function $publicFunctionNames
}

New-Variable -Name "XDRContext" -Value $null -Scope Global -Force
$Global:XDRContext = New-XdrRuntimeContext