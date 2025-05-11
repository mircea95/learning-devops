<#
.EXAMPLE
    .\Generate-IIS-Report.ps1 -LogFolder "C:\inetpub\logs\LogFiles\W3SVC1" -OutputFormat "HTML""
#>
param(
    [string]$LogFolder = "C:\inetpub\logs\LogFiles\W3SVC1",
    [string]$OutputFormat = "CSV"  # Options: CSV, JSON, HTML
)

$logFiles = Get-ChildItem -Path $LogFolder -Filter *.log

$activeHours = @{}
$errorCounts = @{}
$browserStats = @{}

foreach ($file in $logFiles) {
    $lines = Get-Content $file.FullName | Where-Object { $_ -notmatch "^#" }

    foreach ($line in $lines) {
        $cols = $line -split ' '

        if ($cols.Length -lt 10) { continue }

        $time = $cols[1]
        $status = $cols[11]
        $userAgent = $cols[9]

        # Count by hour
        $hour = ($time -split ":")[0]
        $activeHours[$hour] = $activeHours[$hour] + 1

        # Count errors
        if ($status -match "^[45]\d\d$") {
            $errorCounts[$status] = $errorCounts[$status] + 1
        }

        # Count browsers
        if ($userAgent -match "Chrome") { $browserStats["Chrome"]++ }
        elseif ($userAgent -match "Firefox") { $browserStats["Firefox"]++ }
        elseif ($userAgent -match "Safari" -and $userAgent -notmatch "Chrome") { $browserStats["Safari"]++ }
        elseif ($userAgent -match "Edge") { $browserStats["Edge"]++ }
        elseif ($userAgent -match "MSIE|Trident") { $browserStats["Internet Explorer"]++ }
        else { $browserStats["Other"]++ }
    }
}

$report = [PSCustomObject]@{
    ActiveHours = $activeHours
    ErrorSummary = $errorCounts
    BrowserStats = $browserStats
}

switch ($OutputFormat.ToUpper()) {
    "CSV" {
        $report.ActiveHours.GetEnumerator() | Sort-Object Name | Export-Csv -Path "ActiveHours.csv" -NoTypeInformation
        $report.ErrorSummary.GetEnumerator() | Sort-Object Name | Export-Csv -Path "ErrorSummary.csv" -NoTypeInformation
        $report.BrowserStats.GetEnumerator() | Sort-Object Name | Export-Csv -Path "BrowserStats.csv" -NoTypeInformation
        Write-Host "Reports saved as CSV."
    }
    "JSON" {
        $report | ConvertTo-Json -Depth 3 | Out-File -Encoding utf8 "IIS-Report.json"
        Write-Host "Report saved as JSON."
    }
    "HTML" {
        $html = "<html><body><h1>IIS Usage Report</h1>"

        $html += "<h2>Most Active Hours</h2><ul>"
        foreach ($kvp in $activeHours.GetEnumerator() | Sort-Object Name) {
            $html += "<li>$($kvp.Key): $($kvp.Value) hits</li>"
        }
        $html += "</ul><h2>Error Summary</h2><ul>"
        foreach ($kvp in $errorCounts.GetEnumerator()) {
            $html += "<li>$($kvp.Key): $($kvp.Value)</li>"
        }
        $html += "</ul><h2>Browser Statistics</h2><ul>"
        foreach ($kvp in $browserStats.GetEnumerator()) {
            $html += "<li>$($kvp.Key): $($kvp.Value)</li>"
        }
        $html += "</ul></body></html>"

        $html | Out-File -Encoding utf8 "IIS-Report.html"
        Write-Host "Report saved as HTML."
    }
    default {
        Write-Host "Unsupported output format: $OutputFormat"
    }
}
