{ appimageTools, fetchurl }:

let
  pname = "riff";
  version = "44.2.0";

  src = fetchurl {
    url = "https://github.com/rootscripts/riff/releases/download/v${version}/riff-${version}-linux-x86_64.AppImage";
    hash = "sha256-nuQ/OuDFca67bXOr8Hys6uJidxNBVjFfN6e+hL3FJLs=";
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  profile = ''
    export APPIMAGE=riff
  '';

  extraInstallCommands = ''
    install -m 444 -D ${appimageContents}/riff.desktop $out/share/applications/riff.desktop
    install -m 444 -D ${appimageContents}/usr/share/icons/hicolor/1546x1546/apps/riff.png \
      $out/share/icons/hicolor/512x512/apps/riff.png
    substituteInPlace $out/share/applications/riff.desktop \
      --replace-fail 'Exec=AppRun --no-sandbox %U' 'Exec=riff %U'
  '';
}
