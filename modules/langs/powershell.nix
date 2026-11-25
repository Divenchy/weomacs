{
  flake.modules.homeManager.weomacs = {pkgs, ...}: {
    home.packages = with pkgs; [
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

    programs.emacs.extraPackages = epkgs: [epkgs.powershell];

    home.file = {
      ".emacs.d/tree-sitter/libtree-sitter-powershell.so".source = "${pkgs.tree-sitter-grammars.tree-sitter-powershell}/parser";
      ".emacs.d/lsp/langs/powershell.el".source = ../../emacs_elisp/lsp/langs/powershell.el;
    };
  };
}
