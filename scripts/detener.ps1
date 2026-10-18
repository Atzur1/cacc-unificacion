# Frena las dos APIs de prueba (solo los procesos de ApiGestion y CACC.API).
Get-CimInstance Win32_Process |
    Where-Object { $_.CommandLine -match 'ApiGestion\.(csproj|dll|exe)|CACC\.API\.(csproj|dll|exe)' -and $_.Name -match '^(dotnet|ApiGestion|CACC\.API)(\.exe)?$' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Start-Sleep 2
Write-Host 'APIs detenidas.'
