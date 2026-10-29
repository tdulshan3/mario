#ifndef AppVersion
  #define AppVersion "2.0.1"
#endif
#define AppName "Mario"
#define AppPublisher "Mario"
#define AppExeName "Mario.exe"
#define AppUserModelId "com.marionote.app.mario"

[Setup]
AppId={{B4EF1BB4-287C-4B93-A63B-2A394FC88FF3}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL=https://github.com/tdulshan3/mario
AppSupportURL=https://github.com/tdulshan3/mario/issues
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\artifacts\installer
OutputBaseFilename=Mario-{#AppVersion}-windows-x64-setup
SetupIconFile=..\public\assets\logo\mario.ico
UninstallDisplayIcon={app}\mario.ico
UninstallDisplayName={#AppName}
ChangesAssociations=yes
CloseApplications=yes
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional shortcuts:"; Flags: unchecked

[Files]
Source: "..\artifacts\Mario-win32-x64\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\mario.ico"; AppUserModelID: "{#AppUserModelId}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; WorkingDir: "{app}"; IconFilename: "{app}\mario.ico"; AppUserModelID: "{#AppUserModelId}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Launch {#AppName}"; Flags: nowait postinstall skipifsilent
