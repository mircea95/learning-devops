# Define the Prometheus endpoint and the target API endpoint
$prometheusUrl = "http://localhost:9090/metrics"
$apiEndpoint = "https://eonwr8vp7ercf82.m.pipedream.net"

# Create log directory if it doesn't exist
$logPath = "C:\Logs"
if (-not (Test-Path -Path $logPath)) {
    New-Item -ItemType Directory -Path $logPath -Force
}

try {
    # Fetch data from Prometheus
    $prometheusData = Invoke-RestMethod -Uri $prometheusUrl -Method Get
    
    # Convert to JSON and send to the API endpoint
    $jsonData = $prometheusData | ConvertTo-Json -Depth 10
    Invoke-RestMethod -Uri $apiEndpoint -Method Post -Body $jsonData -ContentType "application/json"
    
    # Log success
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - Successfully sent Prometheus data to API" | Out-File -Append -FilePath "$logPath\prometheus_sender.log"
}
catch {
    # Log error
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$timestamp - Error sending Prometheus data: $_" | Out-File -Append -FilePath "$logPath\prometheus_sender.log"
}