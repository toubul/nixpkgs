{
  config,
  lib,
  pkgs,
  ...
}:
let

  cfg = config.hardware.rasdaemon;

in
{
  options.hardware.rasdaemon = {

    enable = lib.mkEnableOption "RAS logging daemon";

    package = lib.mkPackageOption pkgs "rasdaemon" { };

    record = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "record events via sqlite3, required for ras-mc-ctl";
    };

    mainboard = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Custom mainboard description, see {manpage}`ras-mc-ctl(8)` for more details.";
      example = ''
        vendor = ASRock
        model = B450M Pro4

        # it should default to such values from
        # /sys/class/dmi/id/board_[vendor|name]
        # alternatively one can supply a script
        # that returns the same format as above

        script = <path to script>
      '';
    };

    # TODO, accept `rasdaemon.labels = " ";` or `rasdaemon.labels = { dell = " "; asrock = " "; };'

    labels = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional memory module label descriptions to be placed in /etc/ras/dimm_labels.d/labels";
      example = ''
        # vendor and model may be shown by 'ras-mc-ctl --mainboard'
        vendor: ASRock
          product: To Be Filled By O.E.M.
          model: B450M Pro4
            # these labels are names for the motherboard slots
            # the numbers may be shown by `ras-mc-ctl --error-count`
            # they are mc:csrow:channel
            DDR4_A1: 0.2.0;  DDR4_B1: 0.2.1;
            DDR4_A2: 0.3.0;  DDR4_B2: 0.3.1;
      '';
    };

    config = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = ''
        rasdaemon configuration, currently only used for CE PFA
        for details, read rasdaemon.outPath/etc/sysconfig/rasdaemon's comments
      '';
      example = ''
        # defaults from included config
        PAGE_CE_REFRESH_CYCLE="24h"
        PAGE_CE_THRESHOLD="50"
        PAGE_CE_ACTION="soft"
      '';
    };

    extraModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "extra kernel modules to load";
      example = [ "i7core_edac" ];
    };

    testing = lib.mkEnableOption "error injection infrastructure";
  };

  config = lib.mkIf cfg.enable {

    environment.etc = {
      "ras/mainboard" = {
        enable = cfg.mainboard != "";
        text = cfg.mainboard;
      };
      # TODO, handle multiple cfg.labels.brand = " ";
      "ras/dimm_labels.d/labels" = {
        enable = cfg.labels != "";
        text = cfg.labels;
      };
      "sysconfig/rasdaemon" = {
        enable = cfg.config != "";
        text = cfg.config;
      };
    };
    environment.systemPackages = [
      cfg.package
    ]
    ++ lib.optionals (cfg.testing) (
      with pkgs.error-inject;
      [
        edac-inject
        mce-inject
        aer-inject
      ]
    );

    boot.initrd.kernelModules =
      cfg.extraModules
      ++ lib.optionals (cfg.testing) [
        # edac_core and amd64_edac should get loaded automatically
        # i7core_edac may not be, and may not be required, but should load successfully
        "edac_core"
        "amd64_edac"
        "i7core_edac"
        "mce-inject"
        "aer-inject"
      ];

    boot.kernelPatches = lib.optionals (cfg.testing) [
      {
        name = "rasdaemon-tests";
        patch = null;
        extraConfig = ''
          EDAC_DEBUG y
          X86_MCE_INJECT y

          PCIEPORTBUS y
          PCIEAER y
          PCIEAER_INJECT y
        '';
      }
    ];

    # i tried to set up a group for this
    # but rasdaemon needs higher permissions?
    # `rasdaemon: Can't locate a mounted debugfs`

    # most of this taken from src/misc/
    systemd.services = {
      rasdaemon = {
        description = "the RAS logging daemon";
        documentation = [ "man:rasdaemon(1)" ];
        wantedBy = [ "multi-user.target" ];

        serviceConfig = {
          StateDirectory = lib.optionalString (cfg.record) "rasdaemon";

          ExecStart =
            "${cfg.package}/bin/rasdaemon --foreground" + lib.optionalString (cfg.record) " --record";
          ExecStop = "${cfg.package}/bin/rasdaemon --disable";
          Restart = "on-abort";

          # src/misc/rasdaemon.service.in shows this:
          # ExecStartPost = ${cfg.package}/bin/rasdaemon --enable
          # but that results in unpredictable existence of the database
          # and everything seems to be enabled without this...
        };
      };
      ras-mc-ctl = lib.mkIf (cfg.labels != "") {
        description = "register DIMM labels on startup";
        documentation = [ "man:ras-mc-ctl(8)" ];
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${cfg.package}/bin/ras-mc-ctl --register-labels";
          RemainAfterExit = true;
        };
      };
    };
  };

  meta.maintainers = [ lib.maintainers.evils ];

}
