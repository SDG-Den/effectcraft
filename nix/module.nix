# `programs.effectcraft` for NixOS and home-manager.
#
# The option set is shared; `kind` selects only the behaviour the target module system can express:
# home-manager writes the settings overlay and the palette variable per user, NixOS installs the
# package and the MIME defaults for the whole system. NixOS cannot write per-user files, so it
# never writes `settings`.
#
# The overlay is `settings.override.json` beside `prefs.json` (`crates/engine/src/settings/`),
# merged over the saved preferences at start-up. EffectCraft never writes it, so the declarative
# values survive a normal save.
{ kind }:
{
  config,
  lib,
  pkgs,
  # The package of this flake; `flake.nix` passes it through `_module.args`, so importing the
  # module directly needs no overlay.
  effectcraftPackage ? pkgs.effectcraft,
  ...
}:

let
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  cfg = config.programs.effectcraft;

  jsonFormat = pkgs.formats.json { };

  # The MIME types of `packaging/linux/ai.storyteller.effectcraft.desktop`. EffectCraft declares
  # none there (its `.mime.xml` is empty), so `setAsDefault` associates nothing until the desktop
  # file gains a `MimeType=` line.
  mimeTypes = [ ];

  desktopFile = "ai.storyteller.effectcraft.desktop";

  # The per-user settings directory: `$XDG_CONFIG_HOME/effectcraft` on Linux.
  settingsDir = "${config.xdg.configHome}/effectcraft";

  associations = lib.genAttrs mimeTypes (_: [ desktopFile ]);
in
{
  options.programs.effectcraft = {
    enable = mkEnableOption "EffectCraft";

    package = mkOption {
      type = types.package;
      default = effectcraftPackage;
      defaultText = lib.literalMD "the `effectcraft` package of this flake";
      description = "The EffectCraft package to install.";
    };

    setAsDefault = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Open the file types listed in
        `packaging/linux/ai.storyteller.effectcraft.desktop` with EffectCraft by default.
      '';
    };

    settings = mkOption {
      type = jsonFormat.type;
      default = { };
      description = ''
        Free-form preferences merged over the app's settings. Home-manager writes them to
        `settings.override.json`; NixOS ignores them, because it cannot write per-user files.
      '';
    };

    paletteFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = ''
        Optional shared palette file, exported as `CRAFT_PALETTE_FILE` by home-manager. Inert until
        theming support lands. NixOS ignores it.
      '';
    };
  };

  config = lib.mkMerge [
    (mkIf cfg.enable (
      if kind == "nixos" then
        {
          environment.systemPackages = [ cfg.package ];
          xdg.mime.defaultApplications = mkIf cfg.setAsDefault associations;
        }
      else
        {
          home.packages = [ cfg.package ];
          home.sessionVariables = mkIf (cfg.paletteFile != null) {
            CRAFT_PALETTE_FILE = toString cfg.paletteFile;
          };
          home.file."${settingsDir}/settings.override.json" = mkIf (cfg.settings != { }) {
            source = jsonFormat.generate "effectcraft-settings.override.json" cfg.settings;
          };
          xdg.mimeApps = mkIf cfg.setAsDefault {
            enable = true;
            defaultApplications = associations;
            # Associated even when another application stays the default.
            associations.added = associations;
          };
        }
    ))
  ];
}
