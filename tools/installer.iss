; SingFox installer: per-user by default (no UAC), or for all users when the
; choice dialog asks for it. Build with: iscc tools\installer.iss
; after `flutter build windows --release` (core/ comes from build_core.ps1).

#define AppName "SingFox"
#define AppVersion "1.0.2"
#define AppExe "singfox.exe"
#define Bundle "..\build\windows\x64\runner\Release"

[Setup]
AppId={{6E2F3B5A-9C41-4D7E-8A2B-5F0C1D3E7A94}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=fmys2010
AppPublisherURL=https://github.com/fmys2010/SingFox
AppSupportURL=https://github.com/fmys2010/SingFox/issues
AppUpdatesURL=https://github.com/fmys2010/SingFox/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=SingFox-Setup-{#AppVersion}
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
; A running SingFox (and its core) is closed before files are replaced.
CloseApplications=force
RestartApplications=no

[Languages]
Name: "zh"; MessagesFile: "ChineseSimplified.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#Bundle}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\{cm:UninstallProgram,{#AppName}}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent

[UninstallRun]
; The app and its core must not hold files while they are removed.
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExe} /T"; Flags: runhidden; RunOnceId: "KillApp"
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM sing-box.exe /T"; Flags: runhidden; RunOnceId: "KillCore"
; Launch-at-login entries SingFox may have created.
Filename: "{sys}\reg.exe"; Parameters: "delete HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v SingFox /f"; Flags: runhidden; RunOnceId: "DelRunKey"
