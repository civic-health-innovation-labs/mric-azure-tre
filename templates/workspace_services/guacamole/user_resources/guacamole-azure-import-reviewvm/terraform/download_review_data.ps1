$ErrorActionPreference = 'Stop'

$DownloadPath = Join-Path $env:Public "Desktop\ReviewData"
New-Item -ItemType Directory -Force -Path $DownloadPath | Out-Null

function Ensure-Chocolatey {
	if (Get-Command choco -ErrorAction SilentlyContinue) {
		Write-Host "Chocolatey already installed."
		return
	}

	Write-Host "Installing Chocolatey..."
	Set-ExecutionPolicy Bypass -Scope Process -Force
	$ProgressPreference = 'SilentlyContinue'
	[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12
	$script = (New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1')
	Invoke-Expression $script
	$env:PATH += ';C:\ProgramData\chocolatey\bin'
}

if (-not (Get-Command R.exe -ErrorAction SilentlyContinue)) {
	Ensure-Chocolatey
	Write-Host "Installing R via Chocolatey"
	choco install r.project -y --no-progress
} else {
	Write-Host "R is already installed"
}

az storage blob download-batch -d $DownloadPath -s '"${airlock_request_sas_url}"'
