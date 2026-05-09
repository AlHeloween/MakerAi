param(
    [string]$SourceDir = "D:\zPython\MakerAi\Source"
)

$files = Get-ChildItem -Path $SourceDir -Filter '*.pas' -Recurse
$commentLines = @()

foreach ($file in $files) {
    $lines = Get-Content -Path $file.FullName -Encoding UTF8
    $relativePath = $file.FullName.Replace($SourceDir + '\', '')
    $lineNum = 0
    foreach ($line in $lines) {
        $lineNum++
        # Find lines with // comments that contain Spanish accented characters
        if ($line -match '//.*[áéíóúüñÁÉÍÓÚÜÑáéíóúü]') {
            $commentLines += "$relativePath`:$lineNum | $line"
        }
    }
}

Write-Host "Total Spanish comment lines found: $($commentLines.Count)"
$commentLines | Sort-Object -Unique | ForEach-Object { Write-Host $_ }
