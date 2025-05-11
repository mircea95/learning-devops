<powershell>
New-Item -Path "C:\Scripts" -ItemType Directory -Force | Out-Null
Set-Content -Path "C:\\Scripts\\Generate-IIS-Dump.ps1" -Value @'
${generate_iis_dump_script}
'@

Set-Content -Path "C:\\Scripts\\Send-PrometheusData.ps1" -Value @'
${generate_send_prometheus_data_script}
'@

Set-Content -Path "C:\\Scripts\\Generate-IIS-Report.ps1" -Value @'
${generate_iis_report_script}
'@

# Set execution policy
Set-ExecutionPolicy Unrestricted -Force
${configure_winrm_script}
${install_iss}
${install_app}
${scheduled_task}
</powershell>
