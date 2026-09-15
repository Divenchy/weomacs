{pkgs, ...}: let
  tree-sitter-odin = pkgs.tree-sitter.buildGrammar {
    language = "odin";
    version = "unstable";
    src = pkgs.fetchFromGitHub {
      owner = "amaanq";
      repo = "tree-sitter-odin";
      rev = "master";
      sha256 = "sha256-aPeaGERAP1Fav2QAjZy1zXciCuUTQYrsqXaSQsYG0oU=";
    };
  };
in {
  home.packages = with pkgs; [
    dotnet-sdk_11
    csharp-ls
    netcoredbg

    zls
    beamPackages.expert
    beamPackages.elixir-ls
    rust-analyzer
    nil
    clang-tools
    typescript-language-server
    
    yaml-language-server
    powershell-editor-services
    powershell
    (pkgs.writeShellScriptBin "pwsh-ls" ''
      # Define a temporary or persistent path where the module can live isolated from the system
      MODULE_DIR="$HOME/.local/share/powershell/modules"
      mkdir -p "$MODULE_DIR"

      # Automatically fetch/install the required Editor Services module if it is missing
      ${pkgs.powershell}/bin/pwsh -NoProfile -Command "
        if (-not (Get-Module -ListAvailable -Name PowerShellEditorServices)) {
            Write-Host 'Installing PowerShellEditorServices via Nix wrapper...'
            Install-Module -Name PowerShellEditorServices -Force -Scope CurrentUser -Repository PSGallery
        }
      "

      # Execute the language server using the system's native Nix-managed PowerShell binary
      exec ${pkgs.powershell}/bin/pwsh -NoProfile -Command "
        Import-Module PowerShellEditorServices;
        Start-EditorServices \
          -HostName 'Emacs' \
          -HostProfileId 'Emacs.lsp-mode' \
          -HostVersion '1.0.0' \
          -LogPath '$HOME/.local/share/powershell/pwsh-ls.log' \
          -LogLevel 'Normal' \
          -Stdio
      "
    '')
  ];

  programs.emacs = {
    enable = true;
    package = pkgs.emacs;

    extraPackages = epkgs:
      (with epkgs; [
        # Langs
        glsl-mode
        nix-mode
        rust-mode
        zig-mode
        yaml-mode
        dotnet
        powershell
        elixir-ts-mode
        heex-ts-mode
        reformatter
        inf-elixir
        exunit
        mix

        # Dev
        direnv
        magit
        projectile
        perspective
        lsp-mode
        lsp-ui
        lsp-treemacs
        dap-mode
        yasnippet

        # Extendability
        ligature
        multiple-cursors
        corfu
        cape
        compat
        kind-icon
        orderless
        vertico
        marginalia
        consult
        embark
        embark-consult
        rainbow-delimiters
        which-key
        helpful
        avy
        flycheck
        hydra
        vterm
        expand-region
        
        # Note Taking
        pdf-tools
        org
        org-bullets
        eshell-git-prompt
        
        # Presentation
        visual-fill-column
        command-log-mode
        evil-nerd-commenter
        visual-fill-column
        
        # Theming
        doom-themes
        doom-modeline
        ewal
        ef-themes
        sculpture-themes
        hyperstitional-themes
        creamsody-theme
      ])
      ++ [
        (epkgs.trivialBuild {
          pname = "odin-ts-mode";
          version = "unstable";
          src = pkgs.fetchFromGitHub {
            owner = "Sampie159";
            repo = "odin-ts-mode";
            rev = "master";
            sha256 = "JaNwVpNhAUmq3mv/44ryvR7hrZywwEqXpRjFqVpfIKo=";
          };
        })
      ];

    extraConfig = builtins.readFile ./init.el;
  };

  # Symlink weomacs lisp files into ~/.emacs.d
  home.file = {
    ".emacs.d/tree-sitter/libtree-sitter-elixir.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-elixir}/parser";
    ".emacs.d/tree-sitter/libtree-sitter-heex.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-heex}/parser";
    ".emacs.d/tree-sitter/libtree-sitter-odin.so".source = "${tree-sitter-odin}/parser";
    ".emacs.d/tree-sitter/libtree-sitter-yaml.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-yaml}/parser";
    ".emacs.d/tree-sitter/libtree-sitter-powershell.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-powershell}/parser";
    ".emacs.d/tree-sitter/libtree-sitter-zig.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-zig}/parser";
    ".emacs.d/tree-sitter/libtree-sitter-c.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-c}/parser";
    ".emacs.d/tree-sitter/libtree-sitter-cpp.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-cpp}/parser";
    
    ".emacs.d/basic_settings.el".source = ./basic_settings.el;
    ".emacs.d/init.el".source = ./init.el;
    ".emacs.d/eshell.el".source = ./eshell.el;
    ".emacs.d/qol.el".source = ./qol.el;
    ".emacs.d/visible-mark.el".source = ./visible-mark.el;
    ".emacs.d/workflows.el".source = ./workflows.el;
    ".emacs.d/remaps.el".source = ./remaps.el;
    ".emacs.d/themes.el".source = ./themes.el;
    ".emacs.d/org.el".source = ./org.el;
    ".emacs.d/lsp/lsp.el".source = ./lsp/lsp.el;
    ".emacs.d/lsp/debugging.el".source = ./lsp/debugging.el;
    ".emacs.d/lsp/langs/zig.el".source = ./lsp/langs/zig.el;
    ".emacs.d/lsp/langs/yaml.el".source = ./lsp/langs/yaml.el;
    ".emacs.d/lsp/langs/csharp.el".source = ./lsp/langs/csharp.el;
    ".emacs.d/lsp/langs/elixir.el".source = ./lsp/langs/elixir.el;
    ".emacs.d/lsp/langs/powershell.el".source = ./lsp/langs/powershell.el;
    ".emacs.d/lsp/langs/c.el".source = ./lsp/langs/c.el;
  };
}
