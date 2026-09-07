#ifndef AppVersion
  #error AppVersion must be supplied by the build script
#endif
#ifndef ArtifactVersion
  #define ArtifactVersion AppVersion
#endif

[Setup]
AppId={{0478241A-487D-482F-923B-937472DA1D98}
AppName=Mario
AppVersion={#AppVersion}
AppPublisher=Mario
AppPublisherURL=https://github.com/tdulshan3/mario
AppSupportURL=https://github.com/tdulshan3/mario/issues
DefaultDirName={localappdata}\Programs\Mario
DefaultGroupName=Mario
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir=..\..\build
OutputBaseFilename=mario-{#ArtifactVersion}-windows-x64-setup
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\mario.exe
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
UninstallDisplayName=Mario

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Shortcuts:"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "*.lib,*.exp,*.pdb"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\Mario"; Filename: "{app}\mario.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Mario"; Filename: "{app}\mario.exe"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
Filename: "{app}\mario.exe"; Description: "Launch Mario"; Flags: nowait postinstall skipifsilent
