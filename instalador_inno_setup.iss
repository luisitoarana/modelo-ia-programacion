; Compilar con ISCC /DAppVersion=1.0.0 /DBuildVersion=1.0.0+1 instalador_inno_setup.iss
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef BuildVersion
  #define BuildVersion "1.0.0+1"
#endif
[Setup]
AppId={{C47A1192-3B48-426B-95DC-04C5A88B9E31}
AppName=Sistema Explicador Python IA
AppVersion={#AppVersion}
AppPublisher=Investigacion de Tesis
DefaultDirName={localappdata}\SistemaExplicadorPythonIA
PrivilegesRequired=lowest
DisableProgramGroupPage=yes
SetupIconFile=app-desktop\windows\runner\resources\app_icon.ico
OutputDir=release\{#BuildVersion}\instalador
OutputBaseFilename=Instalador_PythonIA_{#AppVersion}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"
[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked
[Files]
Source: "release\{#BuildVersion}\desktop\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{autoprograms}\Sistema Explicador Python IA"; Filename: "{app}\app_desktop.exe"
Name: "{autodesktop}\Sistema Explicador Python IA"; Filename: "{app}\app_desktop.exe"; Tasks: desktopicon
[Run]
Filename: "{app}\app_desktop.exe"; Description: "{cm:LaunchProgram,Sistema Explicador Python IA}"; Flags: nowait postinstall skipifsilent
