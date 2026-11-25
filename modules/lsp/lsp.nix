{
  flake.modules.homeManager.weomacs = {lib, ...}: {
    programs.emacs = {
      # lsp-mode bakes plist-vs-hash-table accessors into its byte-code at compile time (see
      # early-init.el).
      overrides = self: super:
        lib.genAttrs ["lsp-mode" "lsp-ui" "lsp-treemacs" "dap-mode"] (name:
          super.${name}.overrideAttrs (old: {
            env = (old.env or {}) // {LSP_USE_PLISTS = "true";};
          }));

      extraPackages = epkgs: with epkgs; [
        lsp-mode
        lsp-ui
        lsp-treemacs
        dap-mode
        yasnippet
        apheleia
        flycheck
        corfu
        corfu-prescient
        nerd-icons-corfu
        cape
        compat
        kind-icon
      ];
    };

    home.file = {
      ".emacs.d/lsp/lsp.el".source = ../../emacs_elisp/lsp/lsp.el;
      ".emacs.d/lsp/debugging.el".source = ../../emacs_elisp/lsp/debugging.el;
      ".emacs.d/lsp/TestExplorer.el".source = ../../emacs_elisp/lsp/TestExplorer.el;
      ".emacs.d/lsp/refactorer.el".source = ../../emacs_elisp/lsp/refactorer.el;
    };
  };
}
