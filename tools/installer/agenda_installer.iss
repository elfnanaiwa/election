; Inno Setup Script for Agenda Windows Desktop (Flutter)
; Requires: Inno Setup 6+

#define MyAppName "الأجندة القضائية الإلكترونية"
#define MyAppVersion "1.0"
#define MyAppPublisher "Mohammed-Kamal"
#define MyAppURL ""
#define MyAppExeName "agenda.exe"

[Setup]
AppId={{F1A50C3F-27B6-49F5-9F5B-6C9C1E5B7C21}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
DefaultDirName={pf}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=.
OutputBaseFilename=Agenda-Setup-{#MyAppVersion}
Compression=lzma
SolidCompression=yes
ArchitecturesInstallIn64BitMode=x64
DisableWelcomePage=no
DisableDirPage=no
DisableProgramGroupPage=no
WizardStyle=modern
LicenseFile=licence.txt

[Languages]
Name: "arabic"; MessagesFile: "compiler:Languages\\Arabic.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop icon"; GroupDescription: "Additional icons:"; Flags: unchecked

[Files]
; Copy the entire Flutter Windows Release output
; Adjust the Source path if needed
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion restartreplace

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent

; Optional: install VC++ Redistributable silently if you bundle it
;[Files]
;Source: "vcredist\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: ignoreversion
;[Run]
;Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; Flags: waituntilterminated
