{
  stdenv,
  lib,
  fetchzip,
  alsa-lib,
  autoPatchelfHook,
  copyDesktopItems,
  dbus-glib,
  # ffmpeg 7 not supported yet, results in MP4 playback being unavailable
  # https://repo.palemoon.org/MoonchildProductions/UXP/issues/2523
  ffmpeg_6,
  gtk2-x11,
  withGTK3 ? true,
  gtk3,
  libglvnd,
  libXt,
  libpulseaudio,
  makeDesktopItem,
  wrapGAppsHook3,
  writeScript,
  testers,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "palemoon-bin";
  version = "33.8.0";

  src = finalAttrs.passthru.sources."gtk${if withGTK3 then "3" else "2"}";

  preferLocalBuild = true;

  strictDeps = true;

  nativeBuildInputs = [
    autoPatchelfHook
    copyDesktopItems
    wrapGAppsHook3
  ];

  buildInputs = [
    alsa-lib
    dbus-glib
    gtk2-x11
    libXt
    (lib.getLib stdenv.cc.cc)
  ]
  ++ lib.optionals withGTK3 [
    gtk3
  ];

  desktopItems = [
    (makeDesktopItem {
      name = "palemoon-bin";
      desktopName = "Pale Moon Web Browser";
      comment = "Browse the World Wide Web";
      keywords = [
        "Internet"
        "WWW"
        "Browser"
        "Web"
        "Explorer"
      ];
      exec = "palemoon %u";
      terminal = false;
      type = "Application";
      icon = "palemoon";
      categories = [
        "Network"
        "WebBrowser"
      ];
      mimeTypes = [
        "text/html"
        "text/xml"
        "application/xhtml+xml"
        "application/xml"
        "application/rss+xml"
        "application/rdf+xml"
        "image/gif"
        "image/jpeg"
        "image/png"
        "x-scheme-handler/http"
        "x-scheme-handler/https"
        "x-scheme-handler/ftp"
        "x-scheme-handler/chrome"
        "video/webm"
        "application/x-xpinstall"
      ];
      startupNotify = true;
      startupWMClass = "Pale moon";
      extraConfig = {
        X-MultipleArgs = "false";
      };
      actions = {
        "NewTab" = {
          name = "Open new tab";
          exec = "palemoon -new-tab https://start.palemoon.org";
        };
        "NewWindow" = {
          name = "Open new window";
          exec = "palemoon -new-window";
        };
        "NewPrivateWindow" = {
          name = "Open new private window";
          exec = "palemoon -private-window";
        };
        "ProfileManager" = {
          name = "Open the Profile Manager";
          exec = "palemoon --ProfileManager";
        };
      };
    })
  ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/{bin,lib/palemoon}
    cp -R * $out/lib/palemoon/

    ln -s $out/{lib/palemoon,bin}/palemoon

    for iconpath in chrome/icons/default/default{16,32,48} icons/mozicon128; do
      n=''${iconpath//[^0-9]/}
      size=$n"x"$n
      mkdir -p $out/share/icons/hicolor/$size/apps
      ln -s $out/lib/palemoon/browser/"$iconpath".png $out/share/icons/hicolor/$size/apps/palemoon.png
    done

    # Disable built-in updater
    # https://forum.palemoon.org/viewtopic.php?f=5&t=25073&p=197771#p197747
    # > Please do not take this as permission to change, remove, or alter any other preferences as that is forbidden
    # > without express permission according to the Pale Moon Redistribution License.
    # > We are allowing this one and **ONLY** one exception in order to properly facilitate [package manager] repacks.
    install -Dm644 ${./zz-disableUpdater.js} $out/lib/palemoon/browser/defaults/preferences/zz-disableUpdates.js

    runHook postInstall
  '';

  dontWrapGApps = true;

  preFixup = ''
    # Make optional dependencies available
    gappsWrapperArgs+=(
      --prefix LD_LIBRARY_PATH : "${
        lib.makeLibraryPath [
          ffmpeg_6
          libglvnd
          libpulseaudio
        ]
      }"
    )
    wrapGApp $out/lib/palemoon/palemoon
  '';

  passthru = {
    sources =
      let
        urlRegionVariants =
          buildVariant:
          map
            (
              region:
              "https://rm-${region}.palemoon.org/release/palemoon-${finalAttrs.version}.linux-x86_64-${buildVariant}.tar.xz"
            )
            [
              "eu"
              "us"
            ];
      in
      {
        gtk3 = fetchzip {
          urls = urlRegionVariants "gtk3";
          hash = "sha256-cdPFMYlVEr6D+0mH7Mg5nGpf0KvePGLm3Y/ZytdFHHA=";
        };
        gtk2 = fetchzip {
          urls = urlRegionVariants "gtk2";
          hash = "sha256-dgWKmkHl5B1ri3uev63MNz/+E767ip9wJ/YzSog8vdQ=";
        };
      };

    tests.version = testers.testVersion {
      package = finalAttrs.finalPackage;
    };

    updateScript = writeScript "update-palemoon-bin" ''
      #!/usr/bin/env nix-shell
      #!nix-shell -i bash -p common-updater-scripts curl libxml2

      set -eu -o pipefail

      # Only release note announcement == finalized release
      version="$(
        curl -s 'http://www.palemoon.org/releasenotes.shtml' |
        xmllint --html --xpath 'html/body/table/tbody/tr/td/h3/text()' - 2>/dev/null | head -n1 |
        sed 's/v\(\S*\).*/\1/'
      )"

      for variant in gtk3 gtk2; do
        update-source-version palemoon-bin "$version" --ignore-same-version --source-key="sources.$variant"
      done
    '';
  };

  meta = with lib; {
    homepage = "https://www.palemoon.org/";
    description = "Open Source, Goanna-based web browser focusing on efficiency and customization";
    longDescription = ''
      Pale Moon is an Open Source, Goanna-based web browser focusing on
      efficiency and customization.

      Pale Moon offers you a browsing experience in a browser completely built
      from its own, independently developed source that has been forked off from
      Firefox/Mozilla code a number of years ago, with carefully selected
      features and optimizations to improve the browser's stability and user
      experience, while offering full customization and a growing collection of
      extensions and themes to make the browser truly your own.
    '';
    changelog = "https://repo.palemoon.org/MoonchildProductions/Pale-Moon/releases/tag/${finalAttrs.version}_Release";
    license = [
      licenses.mpl20
      {
        fullName = "Pale Moon Redistribution License";
        url = "https://www.palemoon.org/redist.shtml";
        # TODO free, redistributable? Has strict limitations on what modifications may be done & shipped by packagers
      }
    ];
    maintainers = with maintainers; [ OPNA2608 ];
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
    mainProgram = "palemoon";
    platforms = [ "x86_64-linux" ];
    hydraPlatforms = [ ];
  };
})
