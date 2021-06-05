{ config, lib, pkgs, ... }:

with lib;

let

  cfg = config.services.dunst;

  eitherStrBoolIntList = with types;
    either str (either bool (either int (listOf str)));

  toDunstIni = generators.toINI {
    mkKeyValue = key: value:
      let
        value' = if isBool value then
          (if value then "yes" else "no")
        else if isString value then
          ''"${value}"''
        else
          toString value;
      in "${key}=${value'}";
  };

  themeType = types.submodule {
    options = {
      package = mkOption {
        type = types.package;
        example = literalExample "pkgs.gnome.adwaita-icon-theme";
        description = "Package providing the theme.";
      };

      name = mkOption {
        type = types.str;
        example = "Adwaita";
        description = "The name of the theme within the package.";
      };

      size = mkOption {
        type = types.str;
        default = "32x32";
        example = "16x16";
        description = "The desired icon size.";
      };
    };
  };

  hicolorTheme = {
    package = pkgs.hicolor-icon-theme;
    name = "hicolor";
    size = "32x32";
  };

in {
  meta.maintainers = [ maintainers.rycee ];

  options = {
    services.dunst = {
      enable = mkEnableOption "the dunst notification daemon";

      package = mkOption {
        type = types.package;
        default = pkgs.dunst;
        defaultText = literalExample "pkgs.dunst";
        description = "Package providing <command>dunst</command>.";
      };

      iconTheme = mkOption {
        type = themeType;
        default = hicolorTheme;
        description = "Set the icon theme.";
      };

      waylandDisplay = mkOption {
        type = types.str;
        default = "";
        description =
          "Set the service's <envar>WAYLAND_DISPLAY</envar> environment variable.";
      };

      settings = mkOption {
        type = with types; attrsOf (attrsOf eitherStrBoolIntList);
        default = { };
        description = "Configuration written to ~/.config/dunst/dunstrc";
        example = literalExample ''
          {
            global = {
              geometry = "300x5-30+50";
              transparency = 10;
              frame_color = "#eceff1";
              font = "Droid Sans 9";
            };

            urgency_normal = {
              background = "#37474f";
              foreground = "#eceff1";
              timeout = 10;
            };
          };
        '';
      };
    };
  };

  config = mkIf cfg.enable (mkMerge [
    {
      home.packages = [ cfg.package ];

      xdg.dataFile."dbus-1/services/org.knopwob.dunst.service".source =
        "${pkgs.dunst}/share/dbus-1/services/org.knopwob.dunst.service";

      services.dunst.settings.global.icon_path = let
        useCustomTheme = cfg.iconTheme.package != hicolorTheme.package
          || cfg.iconTheme.name != hicolorTheme.name || cfg.iconTheme.size
          != hicolorTheme.size;

        basePaths = [
          "/run/current-system/sw"
          config.home.profileDirectory
          cfg.iconTheme.package
        ] ++ optional useCustomTheme hicolorTheme.package;

        themes = [ cfg.iconTheme ] ++ optional useCustomTheme
          (hicolorTheme // { size = cfg.iconTheme.size; });

        categories = [
          "actions"
          "animations"
          "apps"
          "categories"
          "devices"
          "emblems"
          "emotes"
          "filesystem"
          "intl"
          "legacy"
          "mimetypes"
          "places"
          "status"
          "stock"
        ];
      in concatStringsSep ":" (concatMap (theme:
        concatMap (basePath:
          map (category:
            "${basePath}/share/icons/${theme.name}/${theme.size}/${category}")
          categories) basePaths) themes);

      systemd.user.services.dunst = {
        Unit = {
          Description = "Dunst notification daemon";
          After = [ "graphical-session-pre.target" ];
          PartOf = [ "graphical-session.target" ];
        };

        Service = {
          Type = "dbus";
          BusName = "org.freedesktop.Notifications";
          ExecStart = "${cfg.package}/bin/dunst";
          Environment = optionalString (cfg.waylandDisplay != "")
            "WAYLAND_DISPLAY=${cfg.waylandDisplay}";
        };
      };
    }

    (mkIf (cfg.settings != { }) {
      xdg.configFile."dunst/dunstrc" = {
        text = toDunstIni cfg.settings;
        onChange = ''
          pkillVerbose=""
          if [[ -v VERBOSE ]]; then
            pkillVerbose="-e"
          fi
          $DRY_RUN_CMD ${pkgs.procps}/bin/pkill -u $USER $pkillVerbose dunst || true
          unset pkillVerbose
        '';
      };
    })
  ]);
}
