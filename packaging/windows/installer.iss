; Inno Setup script for the Silent Hills launcher.
; Invoked by packaging/package.py with /DAppVersion /DStageDir /DOutDir.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#ifndef StageDir
  #define StageDir "..\..\stage\windows"
#endif
#ifndef OutDir
  #define OutDir "..\..\out"
#endif

[Setup]
AppId={{8C1F3E8A-5E6B-4B5C-9C3A-2F7D41B6E0A3}
AppName=Silent Hills
AppVersion={#AppVersion}
AppVerName=Silent Hills {#AppVersion}
AppPublisher=Silent Hills Collection
DefaultDirName={autopf}\Silent Hills
DefaultGroupName=Silent Hills
UninstallDisplayIcon={app}\Silent Hills.exe
OutputDir={#OutDir}
OutputBaseFilename=SilentHills-{#AppVersion}-windows-setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequiredOverridesAllowed=dialog
; Lets the in-app updater run us silently over an existing install.
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#StageDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; No "portable" marker is shipped: installed copies keep data in %APPDATA%\Silent Hills.

[Icons]
Name: "{group}\Silent Hills"; Filename: "{app}\Silent Hills.exe"
Name: "{group}\{cm:UninstallProgram,Silent Hills}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\Silent Hills"; Filename: "{app}\Silent Hills.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Silent Hills.exe"; Description: "{cm:LaunchProgram,Silent Hills}"; Flags: nowait postinstall skipifsilent
; After a silent update started by the launcher itself, relaunch it.
Filename: "{app}\Silent Hills.exe"; Flags: nowait; Parameters: "--updated"; Check: WizardSilent
