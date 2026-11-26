{
  lib,
  stdenv,
  pkg-config,
  wayland-scanner,
  wayland-protocols,
  wayland,
  ffmpeg,
}:

stdenv.mkDerivation {
  pname = "ryoku-livewall";
  version = "1.0-ryoku";

  src = ../vendor/ryoku/livewall;

  nativeBuildInputs = [
    pkg-config
    wayland-scanner
    wayland-protocols
  ];

  buildInputs = [
    wayland
    ffmpeg
  ];

  buildPhase = ''
    runHook preBuild
    bash ./build.sh ./ryoku-livewall
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    install -Dm755 ./ryoku-livewall "$out/bin/ryoku-livewall"
    ln -s ryoku-livewall "$out/bin/livewall"
    runHook postInstall
  '';

  meta = {
    description = "Ryoku lightweight Wayland video wallpaper daemon (wl_shm + wlr-layer-shell)";
    homepage = "https://github.com/ryoku-dev/ryoku";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
  };
}
