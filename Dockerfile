# escape=`

# D365 CE Build/Test Server v1.2

# Run with 2 processors and 2 GB of memory otherwise EasyRepro tests might not run

# Azure Container Instances currently only support the LTSC Windows versions
FROM microsoft/dotnet-framework:4.7.2-runtime-windowsservercore-ltsc2016

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Install NuGet CLI
ENV NUGET_VERSION 4.9.2
RUN New-Item -Type Directory $Env:ProgramFiles\NuGet; `
    Invoke-WebRequest -UseBasicParsing https://dist.nuget.org/win-x86-commandline/v$Env:NUGET_VERSION/nuget.exe -OutFile $Env:ProgramFiles\NuGet\nuget.exe;

# Install VS Build Tools
RUN Invoke-WebRequest -UseBasicParsing https://download.visualstudio.microsoft.com/download/pr/aaa9f801-39de-47ad-9333-9b607c71a271/f78504e5f20d0f135bf5282f06447e67/vs_testagent.exe -OutFile vs_TestAgent.exe; `
    Start-Process vs_TestAgent.exe -ArgumentList '--quiet', '--norestart', '--nocache' -NoNewWindow -Wait; `
    Remove-Item -Force vs_TestAgent.exe; `
    Invoke-WebRequest -UseBasicParsing https://download.visualstudio.microsoft.com/download/pr/bea50589-003e-423f-b887-9bf2d70e998c/acfe10c084a64949c1fff4d864ed9b35/vs_buildtools.exe -OutFile vs_BuildTools.exe; `
    # Installer won't detect DOTNET_SKIP_FIRST_TIME_EXPERIENCE if ENV is used, must use setx /M
    setx /M DOTNET_SKIP_FIRST_TIME_EXPERIENCE 1; `
    Start-Process vs_BuildTools.exe `
    -ArgumentList `
    '--add', 'Microsoft.VisualStudio.Workload.MSBuildTools', `
    '--add', 'Microsoft.VisualStudio.Workload.NetCoreBuildTools', `
    '--add', 'Microsoft.VisualStudio.Workload.AzureBuildTools', `
    '--add', 'Microsoft.VisualStudio.Workload.NodeBuildTools', `
    '--add', 'Microsoft.VisualStudio.Workload.WebBuildTools', `
    '--add', 'Microsoft.VisualStudio.Workload.manageddesktopbuildtools', `
    '--add', 'Microsoft.Net.Component.4.7.2.SDK', `
    '--add', 'Microsoft.Component.ClickOnce.MSBuild', `
    '--quiet', '--norestart', '--nocache' `
    -NoNewWindow -Wait; `
    Remove-Item -Force vs_buildtools.exe; `
    Remove-Item -Force -Recurse """${Env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer"""; `
    Remove-Item -Force -Recurse ${Env:TEMP}\*; `
    Remove-Item -Force -Recurse """C:\ProgramData\Package Cache"""

# Install web targets
RUN Invoke-WebRequest -UseBasicParsing https://dotnetbinaries.blob.core.windows.net/dockerassets/MSBuild.Microsoft.VisualStudio.Web.targets.2018.05.zip -OutFile MSBuild.Microsoft.VisualStudio.Web.targets.zip;`
    Expand-Archive MSBuild.Microsoft.VisualStudio.Web.targets.zip -Force -DestinationPath """${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\BuildTools\MSBuild\Microsoft\VisualStudio\v15.0"""; `
    Remove-Item -Force MSBuild.Microsoft.VisualStudio.Web.targets.zip

# Set PATH in one layer to keep image size down.
 RUN setx /M PATH $(${Env:PATH} `
    + """;${Env:ProgramFiles}\NuGet""" `
    + """;${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\TestAgent\Common7\IDE\CommonExtensions\Microsoft\TestWindow""" `
    + """;${Env:ProgramFiles(x86)}\Microsoft Visual Studio\2017\BuildTools\MSBuild\15.0\Bin""" `
    + """;${Env:ProgramFiles(x86)}\Microsoft SDKs\Windows\v10.0A\bin\NETFX 4.7.2 Tools""" `
    + """;${Env:ProgramFiles(x86)}\Microsoft SDKs\ClickOnce\SignTool""")

# Install Targeting Packs
RUN @('4.0', '4.5.2', '4.6.2', '4.7.2') `
    | %{ `
    Invoke-WebRequest -UseBasicParsing https://dotnetbinaries.blob.core.windows.net/referenceassemblies/v${_}.zip -OutFile referenceassemblies.zip; `
    Expand-Archive referenceassemblies.zip -Force -DestinationPath """${Env:ProgramFiles(x86)}\Reference Assemblies\Microsoft\Framework\.NETFramework"""; `
    Remove-Item -Force referenceassemblies.zip; `
    }

# Install Build Agent
ENV VSTS_ACCOUNT_DOWNLOAD_URL "https://vstsagentpackage.azureedge.net/agent/2.148.2/vsts-agent-win-x64-2.148.2.zip"
RUN mkdir C:\BuildAgent; `
    Invoke-WebRequest $Env:VSTS_ACCOUNT_DOWNLOAD_URL -OutFile agent.zip; `
    Expand-Archive agent.zip -DestinationPath c:\BuildAgent -Force; `
    Remove-Item -Force agent.zip

# Install PowerShell Modules
RUN Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force; `
    Install-Module -Name Microsoft.Xrm.Data.Powershell -Force -AllowClobber; `
    Install-Module -Name Microsoft.Xrm.OnlineManagementAPI -Force -AllowClobber; `
    Install-Module -Name Az -Force -AllowClobber; `
    Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force -AllowClobber; `
    Install-Module -Name Microsoft.PowerApps.PowerShell -Force -AllowClobber

# Supress Windows error dialogs
RUN Set-ItemProperty -Path "HKLM:\System\CurrentControlSet\Control\Windows" -Name "ErrorMode" -Value 2; `
    Set-ItemProperty -Path """HKCU:\Software\Microsoft\Windows\Windows Error Reporting""" -Name "DontShowUI" -Value 1

SHELL ["cmd", "/S", "/C"]

# Chocolatey Install
ENV ChocolateyUseWindowsCompression false
RUN @powershell -NoProfile -ExecutionPolicy Bypass -Command "iex ((New-Object System.Net.WebClient).DownloadString('https://chocolatey.org/install.ps1'))" && SET "PATH=%PATH%;%ALLUSERSPROFILE%\chocolatey\bin"

RUN choco config set cachelocation C:\chococache

# Install Additional Packages
RUN choco install `
    git  `
    nodejs `
    azure-cli `
    --confirm `
    --limit-output `
    --timeout 216000 `
    && rmdir /S /Q C:\chococache

# Install Common Node Tools
RUN npm install gulp -g && `
    npm install grunt -g

SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]

# Install Chrome
ENV ChromeInstaller "chrome_installer.exe"
RUN Invoke-WebRequest "https://dl.google.com/chrome/install/375.126/chrome_installer.exe" -OutFile ${Env:TEMP}\${Env:ChromeInstaller}; `
    Start-Process -FilePath ${Env:TEMP}\${Env:ChromeInstaller} -ArgumentList "/silent","/install" -Verb RunAs -Wait; `
    Remove-Item ${Env:TEMP}\${Env:ChromeInstaller}

SHELL ["cmd", "/S", "/C"]

# Start Up
WORKDIR C:/BuildAgent

COPY ./start.* ./
CMD ["start.cmd"]